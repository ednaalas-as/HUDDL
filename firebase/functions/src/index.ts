/**
 * HUDDL Cloud Functions — trusted server-side operations.
 *
 * Business-rule ASSUMPTIONS (marked "ASSUMPTION" below) cover items the design left OPEN.
 * They are deliberately minimal; confirm or change them with Edna.
 */
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue, Timestamp, DocumentReference, Transaction } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { onDocumentCreated, onDocumentWritten, onDocumentDeleted } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions, logger } from "firebase-functions/v2";

initializeApp();
setGlobalOptions({ region: "asia-southeast1", maxInstances: 10 });
const db = getFirestore();
const auth = getAuth();

// ---------------------------------------------------------------------------
// Types & helpers
// ---------------------------------------------------------------------------

type PlayerRef = { id: string; name: string; username: string; photoURL?: string | null };
type Team = { id: string; capacity: number; members: PlayerRef[] };
type Game = {
  host: PlayerRef; title: string; sport: string; status: string; startAt: Timestamp; durationMin: number;
  teams: Team[]; memberIds: string[]; spotsLeft: number; playType: "solo" | "group"; inviteOnly: boolean;
  format: { playersPerTeam: number; teams: number; isCustom: boolean }; rules: { fixedTeams: boolean; noSubs: boolean };
  venueName: string; venueId: string; result?: unknown;
};

const RESULT_FLAG_WINDOW_H = 24;
const EXPIRED_KEEP_DAYS = 30;

function uidOf(req: CallableRequest): string {
  if (!req.auth) throw new HttpsError("unauthenticated", "Please sign in again.");
  return req.auth.uid;
}

function str(v: unknown, field: string, max = 500): string {
  if (typeof v !== "string") throw new HttpsError("invalid-argument", `Missing ${field}.`);
  const s = v.trim();
  if (s.length > max) throw new HttpsError("invalid-argument", `${field} is too long.`);
  return s;
}

async function playerRef(uid: string): Promise<PlayerRef> {
  const snap = await db.doc(`users/${uid}`).get();
  if (!snap.exists) throw new HttpsError("not-found", "Player not found.");
  const u = snap.data()!;
  return { id: uid, name: u.displayName ?? u.username, username: u.username, photoURL: u.photoURL ?? null };
}

async function getGame(tx: Transaction | null, ref: DocumentReference): Promise<Game> {
  const snap = tx ? await tx.get(ref) : await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "This game no longer exists.");
  return snap.data() as Game;
}

function recompute(game: Game): Partial<Game> {
  const memberIds = Array.from(new Set(game.teams.flatMap((t) => t.members.map((m) => m.id))));
  const spotsLeft = game.teams.reduce((n, t) => n + Math.max(0, t.capacity - t.members.length), 0);
  let status = game.status;
  if (status === "open" && spotsLeft === 0) status = "full";
  if (status === "full" && spotsLeft > 0) status = "open";
  return { teams: game.teams, memberIds, spotsLeft, status };
}

async function isBlockedEitherWay(a: string, b: string): Promise<boolean> {
  const [x, y] = await Promise.all([db.doc(`users/${a}/blocked/${b}`).get(), db.doc(`users/${b}/blocked/${a}`).get()]);
  return x.exists || y.exists;
}

type NotifyInput = {
  type: string; title: string; body: string; actor?: PlayerRef | null;
  gameId?: string; postId?: string; teamId?: string; pref?: "invites" | "applications" | "chat" | "reminders";
};

/** Writes an in-app notification; the onNotificationCreated trigger sends the push. */
async function notify(uid: string, n: NotifyInput, id?: string) {
  const ref = id ? db.doc(`notifications/${uid}/items/${id}`) : db.collection(`notifications/${uid}/items`).doc();
  const data: Record<string, unknown> = {
    type: n.type, title: n.title, body: n.body, read: false, resolved: false,
    createdAt: FieldValue.serverTimestamp(), pref: n.pref ?? null,
  };
  if (n.actor) data.actor = n.actor;
  if (n.gameId) data.gameId = n.gameId;
  if (n.postId) data.postId = n.postId;
  if (n.teamId) data.teamId = n.teamId;
  await ref.set(data);
}

async function systemMessage(gameId: string, text: string) {
  const chatRef = db.doc(`chats/game_${gameId}`);
  await chatRef.collection("messages").add({ senderId: "system", senderName: "HUDDL", text, system: true, createdAt: FieldValue.serverTimestamp() });
}

async function syncGameChat(gameId: string, game: Game) {
  const members = game.teams.flatMap((t) => t.members);
  await db.doc(`chats/game_${gameId}`).set({
    type: "game", gameId, title: game.title, memberIds: game.memberIds, members,
    readOnly: game.status === "ended" || game.status === "cancelled",
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

// ---------------------------------------------------------------------------
// Auth: username sign-in (email stays private, never sent to other clients)
// ---------------------------------------------------------------------------

export const signInWithUsername = onCall(async (req) => {
  const username = str(req.data?.username, "username", 30).toLowerCase();
  const password = str(req.data?.password, "password", 200);
  const map = await db.doc(`usernames/${username}`).get();
  const fail = new HttpsError("permission-denied", "Wrong username or password");
  if (!map.exists) throw fail;
  const uid = map.data()!.uid as string;
  const user = await auth.getUser(uid).catch(() => null);
  if (!user?.email) throw fail;

  // Verify the password with the Auth REST API (emulator or production).
  const emulator = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const apiKey = process.env.HUDDL_WEB_API_KEY ?? "demo-api-key-not-a-secret";
  const base = emulator ? `http://${emulator}/identitytoolkit.googleapis.com` : "https://identitytoolkit.googleapis.com";
  const res = await fetch(`${base}/v1/accounts:signInWithPassword?key=${apiKey}`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: user.email, password, returnSecureToken: false }),
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    if (String(body?.error?.message ?? "").includes("TOO_MANY_ATTEMPTS")) {
      throw new HttpsError("resource-exhausted", "Too many attempts. Try again in a few minutes.");
    }
    throw fail;
  }
  return { token: await auth.createCustomToken(uid) };
});

// ---------------------------------------------------------------------------
// Applying
// ---------------------------------------------------------------------------

export const applyToGame = onCall(async (req) => {
  const uid = uidOf(req);
  const gameId = str(req.data?.gameId, "gameId", 100);
  const teamId = str(req.data?.teamId, "team", 2);
  const joinAs = req.data?.joinAs === "group" ? "group" : "solo";
  const groupIds: string[] = Array.isArray(req.data?.groupMemberIds) ? req.data.groupMemberIds.slice(0, 5) : [];
  const note = str(req.data?.note ?? "", "note", 300);
  if (req.data?.committed !== true) throw new HttpsError("failed-precondition", "Tick the commitment box to send your application");

  const gameRef = db.doc(`games/${gameId}`);
  const me = await playerRef(uid);
  const group = joinAs === "group" ? await Promise.all(groupIds.filter((g) => g !== uid).map(playerRef)) : [];

  const game = await db.runTransaction(async (tx) => {
    const g = await getGame(tx, gameRef);
    if (g.host.id === uid) throw new HttpsError("failed-precondition", "You're hosting this game.");
    if (g.status !== "open" || g.startAt.toMillis() <= Date.now()) throw new HttpsError("failed-precondition", "This game isn't taking applications anymore.");
    if (g.memberIds.includes(uid)) throw new HttpsError("already-exists", "You're already on the roster.");
    if (joinAs === "group" && g.playType !== "group") throw new HttpsError("failed-precondition", "This game is for solo players.");
    const team = g.teams.find((t) => t.id === teamId);
    if (!team) throw new HttpsError("invalid-argument", "Pick a team.");
    const open = team.capacity - team.members.length;
    if (open <= 0) throw new HttpsError("failed-precondition", `Team ${teamId} is full. Pick Team ${teamId === "A" ? "B" : "A"} to apply.`);
    const size = 1 + group.length;
    if (size > open) throw new HttpsError("failed-precondition", `Your group needs ${size} spots — this team has ${open}`);
    if (group.some((p) => g.memberIds.includes(p.id))) throw new HttpsError("failed-precondition", "Someone in your group is already on the roster.");
    const appRef = gameRef.collection("applications").doc(uid);
    const existing = await tx.get(appRef);
    if (existing.exists && existing.data()!.status === "pending") throw new HttpsError("already-exists", "You've already applied to this game.");
    tx.set(appRef, {
      applicant: me, applicantId: uid, teamId, joinAs, groupMembers: group, note, committed: true,
      status: "pending", via: "apply", createdAt: FieldValue.serverTimestamp(), gameId, gameTitle: g.title,
    });
    return g;
  });
  if (await isBlockedEitherWay(uid, game.host.id)) return { ok: true };
  await notify(game.host.id, {
    type: "applied", title: `${me.name} applied to your game`, body: `${game.title} · ${joinAs === "group" ? `Group of ${1 + group.length}` : `Solo · Team ${teamId}`}`,
    actor: me, gameId, pref: "applications",
  });
  return { ok: true };
});

export const withdrawApplication = onCall(async (req) => {
  const uid = uidOf(req);
  const gameId = str(req.data?.gameId, "gameId", 100);
  const ref = db.doc(`games/${gameId}/applications/${uid}`);
  const snap = await ref.get();
  if (!snap.exists || !["pending", "noRoom"].includes(snap.data()!.status)) throw new HttpsError("failed-precondition", "There's no pending application to withdraw.");
  await ref.update({ status: "withdrawn" });
  return { ok: true };
});

// ---------------------------------------------------------------------------
// Host: accept / decline (transactional capacity checks)
// ---------------------------------------------------------------------------

export const acceptApplication = onCall(async (req) => {
  const uid = uidOf(req);
  const gameId = str(req.data?.gameId, "gameId", 100);
  const applicantId = str(req.data?.applicantId, "applicant", 128);
  const gameRef = db.doc(`games/${gameId}`);
  const appRef = gameRef.collection("applications").doc(applicantId);

  const out = await db.runTransaction(async (tx) => {
    const g = await getGame(tx, gameRef);
    if (g.host.id !== uid) throw new HttpsError("permission-denied", "Only the host can accept players.");
    if (g.startAt.toMillis() <= Date.now() || g.status === "started" || g.status === "ended") throw new HttpsError("failed-precondition", "Rosters are locked — the game has started.");
    if (g.status === "cancelled") throw new HttpsError("failed-precondition", "This game was cancelled.");
    const appSnap = await tx.get(appRef);
    if (!appSnap.exists) throw new HttpsError("not-found", "Application not found.");
    const app = appSnap.data()!;
    if (!["pending", "noRoom"].includes(app.status)) throw new HttpsError("failed-precondition", "This application was already handled.");
    const team = g.teams.find((t) => t.id === app.teamId)!;
    const players: PlayerRef[] = [app.applicant, ...(app.groupMembers ?? [])];
    const open = team.capacity - team.members.length;
    if (players.length > open) {
      tx.update(appRef, { status: "noRoom" });
      return { noRoom: true, filledLast: false, game: g };
    }
    team.members.push(...players);
    const next = { ...g, ...recompute(g) } as Game;
    tx.update(gameRef, recompute(g));
    tx.update(appRef, { status: "accepted" });
    return { noRoom: false, filledLast: next.spotsLeft === 0, game: next, players };
  });

  if (out.noRoom) return { noRoom: true };
  const game = out.game;
  const players = out.players!;
  await syncGameChat(gameId, game);
  const host = game.host;
  for (const p of players) {
    await notify(p.id, { type: "accepted", title: "You're in!", body: `${host.name} accepted you to ${game.title}.`, actor: host, gameId, pref: "applications" });
    await systemMessage(gameId, `${p.name} joined Team ${game.teams.find((t) => t.members.some((m) => m.id === p.id))?.id}`);
  }
  await upsertJoinedActivity(gameId, game, players);
  if (out.filledLast) {
    // Last spot filled: roster locks and remaining applicants are told the game is full.
    const pending = await gameRef.collection("applications").where("status", "in", ["pending", "noRoom"]).get();
    for (const doc of pending.docs) {
      await doc.ref.update({ status: "declined", declineReason: "full" });
      await notify(doc.id, { type: "full", title: `${game.title} is full`, body: "The roster filled up. Find a similar game on Discover.", gameId, pref: "applications" });
    }
  }
  return { ok: true, filledLast: out.filledLast };
});

export const declineApplication = onCall(async (req) => {
  const uid = uidOf(req);
  const gameId = str(req.data?.gameId, "gameId", 100);
  const applicantId = str(req.data?.applicantId, "applicant", 128);
  const reason = str(req.data?.reason ?? "", "reason", 200);
  const g = await getGame(null, db.doc(`games/${gameId}`));
  if (g.host.id !== uid) throw new HttpsError("permission-denied", "Only the host can decline players.");
  const appRef = db.doc(`games/${gameId}/applications/${applicantId}`);
  const snap = await appRef.get();
  if (!snap.exists || !["pending", "noRoom"].includes(snap.data()!.status)) throw new HttpsError("failed-precondition", "This application was already handled.");
  // The reason is private to the host — it is stored but never shown to the applicant.
  await appRef.update({ status: "declined", declineReason: reason || null });
  await notify(applicantId, {
    type: "declined", title: `Update on ${g.title}`,
    body: `${g.host.name} filled this game another way. Thanks for applying — there are more games waiting on Discover.`,
    gameId, pref: "applications",
  });
  return { ok: true };
});

// ---------------------------------------------------------------------------
// Leaving, editing, cancelling
// ---------------------------------------------------------------------------

export const leaveGame = onCall(async (req) => {
  const uid = uidOf(req);
  const gameId = str(req.data?.gameId, "gameId", 100);
  const gameRef = db.doc(`games/${gameId}`);
  const { game, within24h } = await db.runTransaction(async (tx) => {
    const g = await getGame(tx, gameRef);
    if (g.host.id === uid) throw new HttpsError("failed-precondition", "Hosts can't leave their own game — cancel it instead.");
    if (g.startAt.toMillis() <= Date.now()) throw new HttpsError("failed-precondition", "Rosters are locked — the game has started.");
    const team = g.teams.find((t) => t.members.some((m) => m.id === uid));
    if (!team) throw new HttpsError("failed-precondition", "You're not on this roster.");
    team.members = team.members.filter((m) => m.id !== uid);
    tx.update(gameRef, recompute(g));
    tx.set(db.doc(`games/${gameId}/applications/${uid}`), { status: "withdrawn" }, { merge: true });
    return { game: { ...g, ...recompute(g) } as Game, within24h: g.startAt.toMillis() - Date.now() < 24 * 3600 * 1000 };
  });
  if (within24h) {
    // ASSUMPTION: reliability formula is OPEN; we only record late drops so a formula can use them later.
    await db.doc(`users/${uid}`).update({ "stats.lateDrops": FieldValue.increment(1) });
  }
  await syncGameChat(gameId, game);
  const me = await playerRef(uid);
  await systemMessage(gameId, `${me.name} left the game. The spot reopened to applicants.`);
  await notify(game.host.id, { type: "spotLeft", title: `${me.name} left ${game.title}`, body: "Their spot reopened to applicants.", actor: me, gameId, pref: "applications" });
  return { ok: true };
});

export const editGame = onCall(async (req) => {
  const uid = uidOf(req);
  const gameId = str(req.data?.gameId, "gameId", 100);
  const fields = (req.data?.fields ?? {}) as Record<string, unknown>;
  const allowed = ["title", "sport", "venueId", "venueName", "venueAddress", "venuePhotoURL", "latitude", "longitude", "geohash",
    "startAt", "durationMin", "notes", "inviteOnly", "playType", "format"];
  const update: Record<string, unknown> = {};
  for (const k of Object.keys(fields)) if (allowed.includes(k)) update[k] = fields[k];
  if ("title" in update) {
    const t = str(update.title, "title", 60);
    if (!t) throw new HttpsError("invalid-argument", "Add a title so players know what to expect");
    update.title = t;
  }
  if ("startAt" in update) update.startAt = Timestamp.fromMillis(Number(update.startAt));
  const gameRef = db.doc(`games/${gameId}`);
  await db.runTransaction(async (tx) => {
    const g = await getGame(tx, gameRef);
    if (g.host.id !== uid) throw new HttpsError("permission-denied", "Only the host can edit this game.");
    if (["started", "ended", "cancelled"].includes(g.status)) throw new HttpsError("failed-precondition", "This game can't be edited anymore.");
    if ("format" in update) {
      const f = update.format as Game["format"];
      if (f.teams !== 2) throw new HttpsError("invalid-argument", "Custom games use 2 teams");
      if (f.playersPerTeam < 1 || f.playersPerTeam > 6) throw new HttpsError("invalid-argument", "Teams can have up to 6 players");
      if (g.teams.some((t) => t.members.length > f.playersPerTeam)) throw new HttpsError("failed-precondition", "A team already has more players than this format allows.");
      g.teams = g.teams.map((t) => ({ ...t, capacity: f.playersPerTeam }));
      Object.assign(update, recompute(g));
    }
    // Fixed teams and no substitutes are always on and can't be edited.
    tx.update(gameRef, update);
  });
  const g = await getGame(null, gameRef);
  await syncGameChat(gameId, g);
  return { ok: true };
});

export const cancelGame = onCall(async (req) => {
  const uid = uidOf(req);
  const gameId = str(req.data?.gameId, "gameId", 100);
  const gameRef = db.doc(`games/${gameId}`);
  const g = await getGame(null, gameRef);
  if (g.host.id !== uid) throw new HttpsError("permission-denied", "Only the host can cancel this game.");
  if (["ended", "cancelled"].includes(g.status)) throw new HttpsError("failed-precondition", "This game already ended.");
  await cancelGameCascade(gameId, g, `${g.host.name} cancelled ${g.title}.`);
  return { ok: true };
});

async function cancelGameCascade(gameId: string, g: Game, body: string) {
  const gameRef = db.doc(`games/${gameId}`);
  await gameRef.update({ status: "cancelled" });
  await db.doc(`chats/game_${gameId}`).set({ readOnly: true }, { merge: true });
  const apps = await gameRef.collection("applications").where("status", "in", ["pending", "noRoom"]).get();
  const notifyIds = new Set<string>([...g.memberIds.filter((m) => m !== g.host.id), ...apps.docs.map((d) => d.id)]);
  for (const d of apps.docs) await d.ref.update({ status: "declined", declineReason: "cancelled" });
  for (const id of notifyIds) await notify(id, { type: "cancelled", title: "Game cancelled", body, gameId, pref: "applications" });
  await systemMessage(gameId, "This game was cancelled.");
}

// ---------------------------------------------------------------------------
// Personal invites
// ---------------------------------------------------------------------------

export const invitePlayer = onCall(async (req) => {
  const uid = uidOf(req);
  const gameId = str(req.data?.gameId, "gameId", 100);
  const inviteeId = str(req.data?.inviteeId, "player", 128);
  const teamId = str(req.data?.teamId, "team", 2);
  const message = str(req.data?.message ?? "", "message", 300);
  const g = await getGame(null, db.doc(`games/${gameId}`));
  if (g.host.id !== uid) throw new HttpsError("permission-denied", "Only the host can invite players.");
  if (g.status !== "open" || g.startAt.toMillis() <= Date.now()) throw new HttpsError("failed-precondition", "This game has no open spots.");
  const invitee = await playerRef(inviteeId);
  if (g.memberIds.includes(inviteeId)) throw new HttpsError("already-exists", `${invitee.name.split(" ")[0]} is already on the roster`);
  const team = g.teams.find((t) => t.id === teamId);
  if (!team || team.members.length >= team.capacity) throw new HttpsError("failed-precondition", `Team ${teamId} is full.`);
  // Respect the invitee's privacy setting and blocks (silently).
  const inviteeDoc = (await db.doc(`users/${inviteeId}`).get()).data()!;
  const pref = inviteeDoc.settings?.whoCanInvite ?? "everyone";
  if (pref === "none" || await isBlockedEitherWay(uid, inviteeId)) {
    throw new HttpsError("permission-denied", `${invitee.name.split(" ")[0]} isn't accepting invites right now.`);
  }
  if (pref === "played") {
    const shared = await db.collection("games").where("memberIds", "array-contains", inviteeId).where("status", "==", "ended").get();
    if (!shared.docs.some((d) => (d.data().memberIds as string[]).includes(uid))) {
      throw new HttpsError("permission-denied", `${invitee.name.split(" ")[0]} only accepts invites from players they've played with.`);
    }
  }
  const inviteRef = db.doc(`games/${gameId}/invites/${inviteeId}`);
  const existing = await inviteRef.get();
  if (existing.exists && existing.data()!.status === "sent") {
    throw new HttpsError("already-exists", `${invitee.name.split(" ")[0]} already has an invite to this game`);
  }
  const host = await playerRef(uid);
  await inviteRef.set({ invitee, invitedBy: host, teamId, message, status: "sent", createdAt: FieldValue.serverTimestamp(), gameId, gameTitle: g.title });
  await notify(inviteeId, {
    type: "invite", title: `${host.name} invited you personally`, body: message || `Join Team ${teamId} in ${g.title}.`,
    actor: host, gameId, teamId, pref: "invites",
  }, `invite_${gameId}`);
  return { ok: true };
});

export const cancelInvite = onCall(async (req) => {
  const uid = uidOf(req);
  const gameId = str(req.data?.gameId, "gameId", 100);
  const inviteeId = str(req.data?.inviteeId, "player", 128);
  const g = await getGame(null, db.doc(`games/${gameId}`));
  if (g.host.id !== uid) throw new HttpsError("permission-denied", "Only the host can cancel invites.");
  await db.doc(`games/${gameId}/invites/${inviteeId}`).update({ status: "cancelled" });
  await db.doc(`notifications/${inviteeId}/items/invite_${gameId}`).delete().catch(() => undefined);
  return { ok: true };
});

export const respondInvite = onCall(async (req) => {
  const uid = uidOf(req);
  const gameId = str(req.data?.gameId, "gameId", 100);
  const accept = req.data?.accept === true;
  const gameRef = db.doc(`games/${gameId}`);
  const inviteRef = gameRef.collection("invites").doc(uid);
  const result = await db.runTransaction(async (tx) => {
    const inv = await tx.get(inviteRef);
    if (!inv.exists || inv.data()!.status !== "sent") throw new HttpsError("failed-precondition", "This invite is no longer available.");
    const g = await getGame(tx, gameRef);
    if (!accept) { tx.update(inviteRef, { status: "declined" }); return { game: g, teamId: inv.data()!.teamId as string }; }
    if (g.status !== "open" || g.startAt.toMillis() <= Date.now()) throw new HttpsError("failed-precondition", "This game is no longer taking players.");
    const teamId = inv.data()!.teamId as string;
    const team = g.teams.find((t) => t.id === teamId)!;
    if (team.members.length >= team.capacity) throw new HttpsError("failed-precondition", `Team ${teamId} filled up before you accepted.`);
    team.members.push(inv.data()!.invitee);
    tx.update(gameRef, recompute(g));
    tx.update(inviteRef, { status: "accepted" });
    tx.set(gameRef.collection("applications").doc(uid), {
      applicant: inv.data()!.invitee, applicantId: uid, teamId, joinAs: "solo", groupMembers: [], note: "", committed: true,
      status: "accepted", via: "invite", createdAt: FieldValue.serverTimestamp(), gameId, gameTitle: g.title,
    });
    return { game: { ...g, ...recompute(g) } as Game, teamId };
  });
  await db.doc(`notifications/${uid}/items/invite_${gameId}`).update({ resolved: true, read: true, type: accept ? "accepted" : "inviteDeclined" }).catch(() => undefined);
  const me = await playerRef(uid);
  if (accept) {
    await syncGameChat(gameId, result.game);
    await systemMessage(gameId, `${me.name} joined Team ${result.teamId}`);
    await upsertJoinedActivity(gameId, result.game, [me]);
  }
  await notify(result.game.host.id, {
    type: accept ? "accepted" : "inviteDeclined",
    title: accept ? `${me.name} accepted your invite` : `${me.name} declined your invite`,
    body: result.game.title, actor: me, gameId, pref: "invites",
  });
  return { ok: true, teamId: result.teamId };
});

// ---------------------------------------------------------------------------
// Results & posts
// ---------------------------------------------------------------------------

export const postResult = onCall(async (req) => {
  const uid = uidOf(req);
  const gameId = str(req.data?.gameId, "gameId", 100);
  const winner = req.data?.winnerTeamId === "B" ? "B" : "A";
  const sets: { a: number; b: number }[] = Array.isArray(req.data?.sets) ? req.data.sets : [];
  if (sets.length === 0 || sets.length > 5 || sets.some((s) => !Number.isInteger(s.a) || !Number.isInteger(s.b) || s.a < 0 || s.b < 0 || s.a > 99 || s.b > 99)) {
    throw new HttpsError("invalid-argument", "Enter a score for every set.");
  }
  const caption = str(req.data?.caption ?? "", "caption", 1000);
  const mediaURLs: string[] = Array.isArray(req.data?.mediaURLs) ? req.data.mediaURLs.slice(0, 10) : [];
  const gameRef = db.doc(`games/${gameId}`);
  const g = await getGame(null, gameRef);
  // ASSUMPTION: only the host posts the result (who may post is OPEN in the design).
  if (g.host.id !== uid) throw new HttpsError("permission-denied", "Only the host can post the result.");
  if (g.startAt.toMillis() > Date.now()) throw new HttpsError("failed-precondition", "You can post the result after the game starts.");
  if (g.result) throw new HttpsError("already-exists", "The result is already posted.");
  const now = Timestamp.now();
  const result = { winnerTeamId: winner, sets, postedBy: uid, postedAt: now, flagDeadline: Timestamp.fromMillis(now.toMillis() + RESULT_FLAG_WINDOW_H * 3600e3), flagged: false };
  await gameRef.update({ result, status: "ended" });
  const teamA = g.teams.find((t) => t.id === "A")!.members, teamB = g.teams.find((t) => t.id === "B")!.members;
  const scoreLine = sets.map((s) => winner === "A" ? `${s.a}–${s.b}` : `${s.b}–${s.a}`).join(", ");
  const host = await playerRef(uid);
  const post = await db.collection("posts").add({
    author: host, type: "result", gameId, gameTitle: g.title, venueName: g.venueName, gameDate: g.startAt, gameSport: g.sport,
    includeResult: true, result: { sport: g.sport, gameTitle: g.title, winnerTeamId: winner, scoreLine, teamA, teamB },
    media: mediaURLs.map((url) => ({ url, type: "photo" })), caption, tagged: [], actors: [],
    audience: "everyone", visibleTo: [], likeCount: 0, commentCount: 0, repostCount: 0, createdAt: FieldValue.serverTimestamp(),
  });
  for (const m of [...teamA, ...teamB]) {
    const won = (winner === "A" ? teamA : teamB).some((p) => p.id === m.id);
    await db.doc(`users/${m.id}`).update({ "stats.games": FieldValue.increment(1), ...(won ? { "stats.wins": FieldValue.increment(1) } : {}) });
    if (m.id !== uid) {
      await notify(m.id, { type: "result", title: `Result posted · ${g.title}`, body: `Team ${winner} won ${scoreLine}. Spot a mistake? You can flag it within 24 hours.`, actor: host, gameId, postId: post.id, pref: "reminders" });
    }
  }
  await db.doc(`chats/game_${gameId}`).set({ readOnly: true }, { merge: true });
  return { ok: true, postId: post.id };
});

export const createPost = onCall(async (req) => {
  const uid = uidOf(req);
  const gameId = str(req.data?.gameId, "gameId", 100);
  const caption = str(req.data?.caption ?? "", "caption", 2000);
  const media = Array.isArray(req.data?.media) ? req.data.media.slice(0, 10) : [];
  if (!caption && media.length === 0) throw new HttpsError("invalid-argument", "Add a photo, video or caption to post");
  const audience = ["everyone", "gamePlayers", "onlyMe"].includes(req.data?.audience) ? req.data.audience : "everyone";
  const g = await getGame(null, db.doc(`games/${gameId}`));
  if (!g.memberIds.includes(uid)) throw new HttpsError("permission-denied", "Only players from this game can share its moments.");
  if (g.startAt.toMillis() > Date.now()) throw new HttpsError("failed-precondition", "Moments can be shared after the game.");
  const members = g.teams.flatMap((t) => t.members);
  const taggedIds: string[] = Array.isArray(req.data?.taggedIds) ? req.data.taggedIds : [];
  if (taggedIds.some((t) => !g.memberIds.includes(t))) throw new HttpsError("invalid-argument", `Only players from ${g.title} can be tagged`);
  const tagged = members.filter((m) => taggedIds.includes(m.id));
  const author = await playerRef(uid);
  const res = g.result as { winnerTeamId: string; sets: { a: number; b: number }[] } | undefined;
  const includeResult = req.data?.includeResult === true && !!res;
  const visibleTo = audience === "everyone" ? [] : audience === "onlyMe" ? [uid] : g.memberIds;
  const ref = await db.collection("posts").add({
    author, type: "postGame", gameId, gameTitle: g.title, venueName: g.venueName, gameDate: g.startAt, gameSport: g.sport,
    includeResult,
    result: includeResult ? {
      sport: g.sport, gameTitle: g.title, winnerTeamId: res!.winnerTeamId,
      scoreLine: res!.sets.map((s) => res!.winnerTeamId === "A" ? `${s.a}–${s.b}` : `${s.b}–${s.a}`).join(", "),
      teamA: g.teams.find((t) => t.id === "A")!.members, teamB: g.teams.find((t) => t.id === "B")!.members,
    } : null,
    media, caption, tagged, actors: [], audience, visibleTo, likeCount: 0, commentCount: 0, repostCount: 0,
    createdAt: FieldValue.serverTimestamp(),
  });
  for (const t of tagged) if (t.id !== uid) {
    await notify(t.id, { type: "comment", title: `${author.name} tagged you`, body: `In moments from ${g.title}`, actor: author, gameId, postId: ref.id });
  }
  return { postId: ref.id };
});

export const repost = onCall(async (req) => {
  const uid = uidOf(req);
  const postId = str(req.data?.postId, "post", 100);
  const ref = db.doc(`posts/${postId}`);
  const mark = db.doc(`posts/${postId}/reposts/${uid}`);
  const done = await db.runTransaction(async (tx) => {
    const [p, m] = await Promise.all([tx.get(ref), tx.get(mark)]);
    if (!p.exists || p.data()!.audience !== "everyone") throw new HttpsError("not-found", "This post can't be reposted.");
    if (m.exists) return false;
    tx.set(mark, { createdAt: FieldValue.serverTimestamp() });
    tx.update(ref, { repostCount: FieldValue.increment(1) });
    return true;
  });
  return { ok: true, already: !done };
});

// ---------------------------------------------------------------------------
// Direct messages
// ---------------------------------------------------------------------------

export const openDirectChat = onCall(async (req) => {
  const uid = uidOf(req);
  const otherId = str(req.data?.otherId, "player", 128);
  if (otherId === uid) throw new HttpsError("invalid-argument", "You can't message yourself.");
  if (await isBlockedEitherWay(uid, otherId)) throw new HttpsError("permission-denied", "You can't message this player.");
  const id = `dm_${[uid, otherId].sort().join("_")}`;
  const ref = db.doc(`chats/${id}`);
  if (!(await ref.get()).exists) {
    const [a, b] = await Promise.all([playerRef(uid), playerRef(otherId)]);
    await ref.set({ type: "direct", title: "", memberIds: [uid, otherId], members: [a, b], readOnly: false, updatedAt: FieldValue.serverTimestamp(), unread: {} });
  }
  return { chatId: id };
});

// ---------------------------------------------------------------------------
// Account deletion cascade
// ---------------------------------------------------------------------------

export const deleteAccount = onCall(async (req) => {
  const uid = uidOf(req);
  const userSnap = await db.doc(`users/${uid}`).get();
  const username = userSnap.data()?.username;
  // Cancel hosted upcoming games (players are notified).
  const hosted = await db.collection("games").where("host.id", "==", uid).where("status", "in", ["open", "full"]).get();
  for (const d of hosted.docs) await cancelGameCascade(d.id, d.data() as Game, "The host deleted their account, so this game was cancelled.");
  // Remove from joined upcoming games (spots reopen).
  const joined = await db.collection("games").where("memberIds", "array-contains", uid).where("status", "in", ["open", "full"]).get();
  for (const d of joined.docs) {
    await db.runTransaction(async (tx) => {
      const g = await getGame(tx, d.ref);
      for (const t of g.teams) t.members = t.members.filter((m) => m.id !== uid);
      tx.update(d.ref, recompute(g));
    });
  }
  // Delete profile, history and reviews.
  const reviews = await db.collection("reviews").where("revieweeId", "==", uid).get();
  for (const r of reviews.docs) await r.ref.delete();
  const posts = await db.collection("posts").where("author.id", "==", uid).get();
  for (const p of posts.docs) await db.recursiveDelete(p.ref);
  await db.recursiveDelete(db.doc(`users/${uid}`));
  await db.recursiveDelete(db.doc(`notifications/${uid}`));
  if (username) await db.doc(`usernames/${username}`).delete();
  await auth.deleteUser(uid);
  return { ok: true };
});

// ---------------------------------------------------------------------------
// Triggers
// ---------------------------------------------------------------------------

async function upsertJoinedActivity(gameId: string, game: Game, players: PlayerRef[]) {
  if (game.inviteOnly) return;
  const ref = db.doc(`posts/joined_${gameId}`);
  const snap = await ref.get();
  const actors: PlayerRef[] = snap.exists ? snap.data()!.actors : [];
  for (const p of players) if (!actors.some((a) => a.id === p.id)) actors.unshift(p);
  await ref.set({
    author: actors[0], type: "joined", gameId, gameTitle: game.title, venueName: game.venueName, gameDate: game.startAt,
    gameSport: game.sport, spotsLeft: game.spotsLeft, actors, media: [], caption: "", tagged: [], includeResult: false,
    audience: "everyone", visibleTo: [], likeCount: snap.data()?.likeCount ?? 0, commentCount: snap.data()?.commentCount ?? 0,
    repostCount: snap.data()?.repostCount ?? 0, createdAt: FieldValue.serverTimestamp(),
  });
}

export const onGameCreated = onDocumentCreated("games/{gameId}", async (event) => {
  const g = event.data?.data() as Game | undefined;
  if (!g) return;
  const gameId = event.params.gameId;
  await syncGameChat(gameId, g);
  await systemMessage(gameId, `${g.host.name} created ${g.title}`);
  await db.doc(`users/${g.host.id}`).update({ "stats.hosted": FieldValue.increment(1) });
  if (!g.inviteOnly && g.status === "open") {
    await db.doc(`posts/hosting_${gameId}`).set({
      author: g.host, type: "hosting", gameId, gameTitle: g.title, venueName: g.venueName, gameDate: g.startAt, gameSport: g.sport,
      spotsLeft: g.spotsLeft, actors: [], media: [], caption: "", tagged: [], includeResult: false, audience: "everyone", visibleTo: [],
      likeCount: 0, commentCount: 0, repostCount: 0, createdAt: FieldValue.serverTimestamp(),
    });
  }
});

/** Keeps denormalized spotsLeft on activity cards in sync and notifies likers when 1 spot is left. */
export const onGameUpdated = onDocumentWritten("games/{gameId}", async (event) => {
  const before = event.data?.before.data() as Game | undefined;
  const after = event.data?.after.data() as Game | undefined;
  if (!before || !after) return;
  const gameId = event.params.gameId;
  if (before.spotsLeft !== after.spotsLeft) {
    for (const id of [`hosting_${gameId}`, `joined_${gameId}`]) {
      await db.doc(`posts/${id}`).update({ spotsLeft: after.spotsLeft }).catch(() => undefined);
    }
    if (after.spotsLeft === 1 && after.status === "open") {
      const likers = await db.collectionGroup("swipes").where("decision", "==", "interested").get();
      for (const s of likers.docs) {
        if (s.id !== gameId) continue;
        const uid = s.ref.parent.parent!.id;
        if (after.memberIds.includes(uid)) continue;
        await notify(uid, { type: "spotLeft", title: `A game you liked has 1 spot left`, body: after.title, gameId, pref: "reminders" });
      }
    }
  }
  if (["cancelled", "ended"].includes(after.status) && after.status !== before.status) {
    for (const id of [`hosting_${gameId}`, `joined_${gameId}`]) await db.doc(`posts/${id}`).delete().catch(() => undefined);
  }
});

export const onLikeWritten = onDocumentWritten("posts/{postId}/likes/{uid}", async (event) => {
  const existedBefore = event.data?.before.exists, existsAfter = event.data?.after.exists;
  if (existedBefore === existsAfter) return;
  // Transaction keeps the counter from going negative (e.g. a late delete after the post was recreated).
  const ref = db.doc(`posts/${event.params.postId}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const current = Number(snap.data()!.likeCount ?? 0);
    tx.update(ref, { likeCount: Math.max(0, current + (existsAfter ? 1 : -1)) });
  }).catch(() => undefined);
});

export const onCommentCreated = onDocumentCreated("posts/{postId}/comments/{commentId}", async (event) => {
  const c = event.data?.data();
  if (!c) return;
  const postRef = db.doc(`posts/${event.params.postId}`);
  await postRef.update({ commentCount: FieldValue.increment(1) });
  const post = (await postRef.get()).data();
  if (post && post.author?.id !== c.author.id) {
    await notify(post.author.id, { type: "comment", title: `${c.author.name} commented on your post`, body: String(c.text).slice(0, 120), actor: c.author, postId: event.params.postId, pref: "chat" });
  }
});

export const onCommentDeleted = onDocumentDeleted("posts/{postId}/comments/{commentId}", async (event) => {
  await db.doc(`posts/${event.params.postId}`).update({ commentCount: FieldValue.increment(-1) }).catch(() => undefined);
});

export const onHelpfulCreated = onDocumentCreated("reviews/{reviewId}/helpful/{uid}", async (event) => {
  await db.doc(`reviews/${event.params.reviewId}`).update({ helpfulCount: FieldValue.increment(1) });
});

/** Maintains users/{blocked}/private/blockedBy so content can be hidden both ways, privately. */
export const onBlockWritten = onDocumentWritten("users/{uid}/blocked/{otherId}", async (event) => {
  const { uid, otherId } = event.params;
  const ref = db.doc(`users/${otherId}/private/blockedBy`);
  if (event.data?.after.exists) await ref.set({ uids: FieldValue.arrayUnion(uid) }, { merge: true });
  else await ref.set({ uids: FieldValue.arrayRemove(uid) }, { merge: true });
});

export const onMessageCreated = onDocumentCreated("chats/{chatId}/messages/{messageId}", async (event) => {
  const m = event.data?.data();
  if (!m) return;
  const chatRef = db.doc(`chats/${event.params.chatId}`);
  const chat = (await chatRef.get()).data();
  if (!chat) return;
  const preview = m.system ? m.text : m.imageURL && !m.text ? `${m.senderName} sent a photo` : `${m.senderName.split(" ")[0]}: ${m.text}`;
  const unread: Record<string, unknown> = {};
  for (const id of chat.memberIds as string[]) if (id !== m.senderId) unread[`unread.${id}`] = FieldValue.increment(1);
  await chatRef.update({ lastMessage: preview, lastSenderId: m.senderId, updatedAt: FieldValue.serverTimestamp(), ...unread });
  if (m.system) return;
  for (const id of chat.memberIds as string[]) {
    if (id === m.senderId) continue;
    await sendPush(id, "chat", chat.type === "direct" ? m.senderName : chat.title, m.text ?? "Sent a photo", { chatId: event.params.chatId });
  }
});

export const onNotificationCreated = onDocumentCreated("notifications/{uid}/items/{id}", async (event) => {
  const n = event.data?.data();
  if (!n) return;
  await sendPush(event.params.uid, n.pref, n.title, n.body, { gameId: n.gameId ?? "", postId: n.postId ?? "", type: n.type });
});

async function sendPush(uid: string, pref: string | null, title: string, body: string, data: Record<string, string>) {
  const user = (await db.doc(`users/${uid}`).get()).data();
  if (!user?.fcmToken) return;
  if (pref && user.settings?.notifications?.[pref] === false) return;
  try {
    await getMessaging().send({ token: user.fcmToken, notification: { title, body }, data, apns: { payload: { aps: { sound: "default" } } } });
  } catch (e) {
    logger.warn("push failed", e);
  }
}

// ---------------------------------------------------------------------------
// Scheduled lifecycle: start → lock rosters / Expired; end → read-only chat + share prompt
// ASSUMPTION: a game "ends" at startAt + durationMin (default 120). A game moves to Expired for
// likers when it starts or fills up. Expired items are kept for 30 days.
// ---------------------------------------------------------------------------

export const gameLifecycle = onSchedule("every 10 minutes", async () => {
  await runLifecycle();
});

export async function runLifecycle(now = Date.now()) {
  const due = await db.collection("games").where("status", "in", ["open", "full"]).where("startAt", "<=", Timestamp.fromMillis(now)).get();
  for (const d of due.docs) {
    const g = d.data() as Game;
    await d.ref.update({ status: "started" });
    const pending = await d.ref.collection("applications").where("status", "in", ["pending", "noRoom"]).get();
    for (const a of pending.docs) await a.ref.update({ status: "declined", declineReason: "started" });
    const likers = await db.collectionGroup("swipes").where("decision", "==", "interested").get();
    for (const s of likers.docs) {
      if (s.id !== d.id) continue;
      const uid = s.ref.parent.parent!.id;
      if (g.memberIds.includes(uid)) continue;
      await notify(uid, { type: "expired", title: `${g.title} started and moved to Interested · Expired`, body: "Find a similar game on Discover.", gameId: d.id, pref: "reminders" });
    }
  }
  const started = await db.collection("games").where("status", "==", "started").get();
  for (const d of started.docs) {
    const g = d.data() as Game;
    if (g.startAt.toMillis() + (g.durationMin ?? 120) * 60e3 > now) continue;
    await d.ref.update({ status: "ended" });
    await db.doc(`chats/game_${d.id}`).set({ readOnly: true }, { merge: true });
    await systemMessage(d.id, "Game ended · chat is read-only");
    for (const uid of g.memberIds) {
      await notify(uid, { type: "ended", title: `${g.title} has ended. Share your photos and moments!`, body: "Post your highlights for the community.", gameId: d.id, pref: "reminders" }, `ended_${d.id}`);
    }
  }
  // Purge Expired items older than 30 days.
  const cutoff = Timestamp.fromMillis(now - EXPIRED_KEEP_DAYS * 24 * 3600e3);
  const old = await db.collectionGroup("swipes").where("createdAt", "<", cutoff).get();
  for (const s of old.docs) {
    const g = await db.doc(`games/${s.id}`).get();
    if (!g.exists || (g.data() as Game).startAt.toMillis() < cutoff.toMillis()) await s.ref.delete();
  }
}

/** Dev-only callable so the lifecycle can be exercised in the emulator without waiting for the scheduler. */
export const devRunLifecycle = onCall(async () => {
  if (!process.env.FUNCTIONS_EMULATOR) throw new HttpsError("permission-denied", "Emulator only.");
  await runLifecycle();
  return { ok: true };
});
