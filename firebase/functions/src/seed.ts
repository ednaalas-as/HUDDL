/**
 * Seeds HUDDL with Edna's 8 players — each gets a REAL Firebase Auth account, a profile and a
 * reserved username — plus venues, games, results, posts and chats so every flow can be tested.
 *
 * Emulator (default):   npm run build && npm run seed
 * Real project (later): HUDDL_SEED_PRODUCTION=1 GOOGLE_APPLICATION_CREDENTIALS=key.json npm run seed
 *
 * Temporary passwords are written ONLY to seed-credentials.local.json (git-ignored).
 * Players should change them with "Forgot password?" once real emails are set.
 */
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { randomBytes } from "crypto";
import { writeFileSync, existsSync, readFileSync } from "fs";
import { join } from "path";

const production = process.env.HUDDL_SEED_PRODUCTION === "1";
if (!production) {
  process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
  process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
  process.env.GCLOUD_PROJECT ??= "demo-huddl";
  process.env.FIREBASE_STORAGE_EMULATOR_HOST ??= "127.0.0.1:9199";
}
initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const auth = getAuth();
const db = getFirestore();

// Optional overrides: real emails per username, kept local and git-ignored.
const localPath = join(__dirname, "..", "seed-credentials.local.json");
const existing: Record<string, { email: string; password: string }> = existsSync(localPath) ? JSON.parse(readFileSync(localPath, "utf8")) : {};

type Seed = { username: string; name: string; sport: string; skill: string };
const PLAYERS: Seed[] = [
  { username: "ednaalas-as", name: "Edna Alas-as", sport: "volleyball", skill: "intermediate" },
  { username: "beaannebalmes", name: "Bea Anne Balmes", sport: "volleyball", skill: "advanced" },
  { username: "roselledeleon", name: "Roselle Jean De Leon", sport: "badminton", skill: "intermediate" },
  { username: "kyleabandia", name: "Kyle Allen Abandia", sport: "badminton", skill: "advanced" },
  { username: "jhonlloydvalencia", name: "Jhon Lloyd Valencia", sport: "chess", skill: "advanced" },
  { username: "thessasurell", name: "Thessalonica Surell", sport: "chess", skill: "intermediate" },
  { username: "altheaaringo", name: "Althea Trisha Mae Aringo", sport: "billiards", skill: "intermediate" },
  { username: "desireeferrer", name: "Desiree Ann Ferrer", sport: "billiards", skill: "beginner" },
];

const B32 = "0123456789bcdefghjkmnpqrstuvwxyz";
function geohash(lat: number, lon: number, precision = 9) {
  let latR = [-90, 90], lonR = [-180, 180], hash = "", bit = 0, ch = 0, even = true;
  while (hash.length < precision) {
    const r = even ? lonR : latR, v = even ? lon : lat, mid = (r[0] + r[1]) / 2;
    if (v >= mid) { ch |= 1 << (4 - bit); r[0] = mid; } else r[1] = mid;
    even = !even;
    if (bit < 4) bit++; else { hash += B32[ch]; bit = 0; ch = 0; }
  }
  return hash;
}
const LUCENA = { name: "Lucena City", latitude: 13.9414, longitude: 121.6234, geohash: geohash(13.9414, 121.6234) };

// Venues named in the design (coordinates approximate; no photos → neutral placeholder covers).
const VENUES = [
  { id: "inigos", name: "Iñigo’s Sports Center", address: "Lucena City, Quezon", lat: 13.9468, lon: 121.6131, sports: ["tennis", "basketball", "badminton"] },
  { id: "tennisclub", name: "Lucena Tennis Club", address: "Lucena City, Quezon", lat: 13.9372, lon: 121.6127, sports: ["tennis", "pickleball"] },
  { id: "mseuf", name: "MSEUF Gymnasium", address: "Lucena City, Quezon", lat: 13.9446, lon: 121.6182, sports: ["volleyball", "basketball", "badminton", "chess"] },
  { id: "pacificmall", name: "Pacific Mall Courts", address: "Lucena City, Quezon", lat: 13.9325, lon: 121.6176, sports: ["badminton", "basketball", "billiards"] },
  { id: "convention", name: "Quezon Convention Gym", address: "Lucena City, Quezon", lat: 13.9390, lon: 121.6080, sports: ["volleyball", "basketball", "chess"] },
  { id: "dalahican", name: "Dalahican Beach", address: "Dalahican, Lucena City", lat: 13.9047, lon: 121.6309, sports: ["volleyball", "football"] },
];

const now = Date.now();

/** Deletes a document and its known subcollections, or every doc in a collection, one write at a time. */
async function retry<T>(fn: () => Promise<T>, tries = 4): Promise<T> {
  for (let i = 1; ; i++) {
    try { return await fn(); } catch (e) { if (i >= tries) throw e; await new Promise((r) => setTimeout(r, 500 * i)); }
  }
}

async function wipe(ref: FirebaseFirestore.DocumentReference | FirebaseFirestore.CollectionReference): Promise<void> {
  if ("listDocuments" in ref) {
    for (const d of await retry(() => ref.listDocuments())) await wipe(d);
    return;
  }
  for (const sub of await retry(() => ref.listCollections())) await wipe(sub);
  await retry(() => ref.delete());
}
const hours = (h: number) => Timestamp.fromMillis(now + h * 3600e3);
type Ref = { id: string; name: string; username: string; photoURL: null };

async function upsertUser(p: Seed): Promise<Ref> {
  const creds = existing[p.username] ?? { email: `${p.username.replace(/[^a-z0-9]/g, "")}@huddl.test`, password: `Huddl-${randomBytes(4).toString("hex")}9` };
  existing[p.username] = creds;
  let uid: string;
  try {
    uid = (await auth.getUserByEmail(creds.email)).uid;
    await auth.updateUser(uid, { password: creds.password, displayName: p.name });
  } catch {
    uid = (await auth.createUser({ email: creds.email, password: creds.password, displayName: p.name })).uid;
  }
  await db.doc(`usernames/${p.username}`).set({ uid });
  await db.doc(`users/${uid}`).set({
    username: p.username, displayName: p.name, city: "Lucena City", homeArea: LUCENA,
    sports: [{ sport: p.sport, skill: p.skill }], stats: { games: 0, wins: 0, hosted: 0 },
    settings: { notifications: { invites: true, applications: true, chat: true, reminders: true }, whoCanInvite: "everyone" },
    profileComplete: true, createdAt: FieldValue.serverTimestamp(),
  });
  return { id: uid, name: p.name, username: p.username, photoURL: null };
}

function game(id: string, host: Ref, o: {
  title: string; sport: string; venue: string; startH: number; ppt: number; playType: "solo" | "group";
  a: Ref[]; b: Ref[]; status?: string; inviteOnly?: boolean; notes?: string; custom?: boolean;
}) {
  const v = VENUES.find((x) => x.id === o.venue)!;
  const teams = [{ id: "A", capacity: o.ppt, members: o.a }, { id: "B", capacity: o.ppt, members: o.b }];
  const spotsLeft = teams.reduce((n, t) => n + (t.capacity - t.members.length), 0);
  return {
    id, data: {
      host, title: o.title, sport: o.sport, venueId: v.id, venueName: v.name, venueAddress: v.address, venuePhotoURL: null,
      latitude: v.lat, longitude: v.lon, geohash: geohash(v.lat, v.lon), startAt: hours(o.startH), durationMin: 120,
      notes: o.notes ?? null, format: { playersPerTeam: o.ppt, teams: 2, isCustom: !!o.custom }, playType: o.playType,
      rules: { fixedTeams: true, noSubs: true }, inviteOnly: !!o.inviteOnly,
      status: o.status ?? (spotsLeft === 0 ? "full" : "open"), teams,
      memberIds: [...o.a, ...o.b].map((m) => m.id), spotsLeft, createdAt: FieldValue.serverTimestamp(),
    },
  };
}

async function main() {
  console.log(`Seeding ${production ? "PRODUCTION" : "emulator"} project ${process.env.GCLOUD_PROJECT}…`);
  const u: Record<string, Ref> = {};
  for (const p of PLAYERS) u[p.username] = await upsertUser(p);
  const [edna, bea, roselle, kyle, jhon, thessa, althea, desiree] = PLAYERS.map((p) => u[p.username]);

  for (const v of VENUES) {
    await db.doc(`venues/${v.id}`).set({ name: v.name, address: v.address, latitude: v.lat, longitude: v.lon, geohash: geohash(v.lat, v.lon), photoURL: null, sports: v.sports });
  }

  const games = [
    game("sat-6v6-open", bea, { title: "Saturday 6v6 Open", sport: "volleyball", venue: "mseuf", startH: 72, ppt: 6, playType: "group", a: [bea, desiree], b: [althea], notes: "Friendly but competitive. Bring water!" }),
    game("friday-doubles", roselle, { title: "Friday Night Doubles", sport: "badminton", venue: "pacificmall", startH: 50, ppt: 2, playType: "solo", a: [roselle, kyle], b: [] }),
    game("rapid-chess", jhon, { title: "Rapid Chess Ladder", sport: "chess", venue: "convention", startH: 30, ppt: 1, playType: "solo", a: [jhon], b: [] }),
    game("eight-ball-night", althea, { title: "8-Ball Night", sport: "billiards", venue: "pacificmall", startH: 98, ppt: 2, playType: "group", a: [althea], b: [] }),
    game("beach-volley", edna, { title: "Beach Volley Sunday", sport: "volleyball", venue: "dalahican", startH: 120, ppt: 2, playType: "solo", a: [edna], b: [bea] }),
    game("badminton-clinic", kyle, { title: "Badminton Smash Session", sport: "badminton", venue: "inigos", startH: 26, ppt: 1, playType: "solo", a: [kyle], b: [] }),
    // Ended game with a posted result (feeds Home, profiles and "Result & moments").
    game("morning-rally", edna, { title: "Morning Rally 2v2", sport: "volleyball", venue: "convention", startH: -26, ppt: 2, playType: "group", a: [edna, bea], b: [thessa, desiree], status: "ended" }),
    // Ended game with NO result yet, so the host can test Post result → Result posted.
    game("sunset-scrimmage", edna, { title: "Sunset Scrimmage", sport: "volleyball", venue: "dalahican", startH: -5, ppt: 2, playType: "solo", a: [edna, roselle], b: [jhon, kyle], status: "ended" }),
  ];
  // Remove games/posts/chats created by earlier test runs so every seed starts from the same state.
  const seedIds = new Set(games.map((g) => g.id));
  for (const d of (await db.collection("games").get()).docs) if (!seedIds.has(d.id)) await wipe(d.ref);
  for (const d of (await db.collection("posts").get()).docs) await wipe(d.ref);
  for (const d of (await db.collection("chats").get()).docs) await wipe(d.ref);
  for (const p of Object.values(u)) {
    await wipe(db.collection(`notifications/${p.id}/items`));
    await wipe(db.collection(`users/${p.id}/swipes`));
    await wipe(db.collection(`users/${p.id}/blocked`));
    await wipe(db.collection(`users/${p.id}/hiddenPosts`));
    await wipe(db.collection(`users/${p.id}/private`));
  }
  // Let delete-triggers from the wipe finish before recreating docs with the same ids.
  await new Promise((r) => setTimeout(r, 4000));
  for (const g of games) {
    await wipe(db.collection(`games/${g.id}/applications`));
    await wipe(db.collection(`games/${g.id}/invites`));
    await db.doc(`games/${g.id}`).set(g.data);
  }
  // Team chats for every seed game (the create trigger only runs for brand-new game ids).
  for (const g of games) {
    const d = g.data as Record<string, any>;
    const members = (d.teams as { members: Ref[] }[]).flatMap((t) => t.members);
    await db.doc(`chats/game_${g.id}`).set({
      type: "game", gameId: g.id, title: d.title, memberIds: d.memberIds, members,
      readOnly: d.status === "ended" || d.status === "cancelled", updatedAt: FieldValue.serverTimestamp(), unread: {},
    });
    await db.collection(`chats/game_${g.id}/messages`).add({
      senderId: "system", senderName: "HUDDL", text: `${d.host.name} created ${d.title}`, system: true, createdAt: FieldValue.serverTimestamp(),
    });
  }

  // Hosted counts (the create trigger doesn't fire when a seed game already existed).
  for (const p of Object.values(u)) {
    await db.doc(`users/${p.id}`).update({ "stats.hosted": games.filter((g) => (g.data.host as Ref).id === p.id).length });
  }

  for (const g of games) {
    const d = g.data as Record<string, any>;
    if (d.status !== "open" || d.inviteOnly) continue;
    await db.doc(`posts/hosting_${g.id}`).set({
      author: d.host, type: "hosting", gameId: g.id, gameTitle: d.title, venueName: d.venueName, gameDate: d.startAt, gameSport: d.sport,
      spotsLeft: d.spotsLeft, actors: [], media: [], caption: "", tagged: [], includeResult: false, audience: "everyone", visibleTo: [],
      likeCount: 0, commentCount: 0, repostCount: 0, createdAt: hours(-6),
    });
  }

  // Result for the ended game.
  const result = { winnerTeamId: "A", sets: [{ a: 25, b: 21 }, { a: 25, b: 19 }], postedBy: edna.id, postedAt: hours(-23), flagDeadline: hours(1), flagged: false };
  await db.doc("games/morning-rally").update({ result });
  for (const m of [edna, bea, thessa, desiree]) {
    await db.doc(`users/${m.id}`).update({ "stats.games": FieldValue.increment(1), ...([edna.id, bea.id].includes(m.id) ? { "stats.wins": FieldValue.increment(1) } : {}) });
  }
  const teamA = [edna, bea], teamB = [thessa, desiree];
  await db.doc("posts/result-morning-rally").set({
    author: edna, type: "result", gameId: "morning-rally", gameTitle: "Morning Rally 2v2", venueName: "Quezon Convention Gym",
    gameDate: hours(-26), gameSport: "volleyball", includeResult: true,
    result: { sport: "volleyball", gameTitle: "Morning Rally 2v2", winnerTeamId: "A", scoreLine: "25–21, 25–19", teamA, teamB },
    media: [], caption: "Great match, everyone! #HUDDL #Volleyball", tagged: [bea], actors: [], audience: "everyone", visibleTo: [],
    likeCount: 0, commentCount: 0, repostCount: 0, createdAt: hours(-23),
  });
  // One photo on Bea's moments post so the full-screen photo viewer can be tested (emulator only).
  let momentMedia: { url: string; type: string }[] = [];
  if (!production) {
    const bucketName = "demo-huddl.appspot.com";
    const dest = `posts/${bea.id}/seed-moment-court.jpg`;
    const token = randomBytes(16).toString("hex");
    await getStorage().bucket(bucketName).upload(join(__dirname, "..", "seed-assets", "moment-court.jpg"), {
      destination: dest, metadata: { contentType: "image/jpeg", metadata: { firebaseStorageDownloadTokens: token } },
    });
    momentMedia = [{ url: `http://127.0.0.1:9199/v0/b/${bucketName}/o/${encodeURIComponent(dest)}?alt=media&token=${token}`, type: "photo" }];
  }
  await db.doc("posts/moments-morning-rally").set({
    author: bea, type: "postGame", gameId: "morning-rally", gameTitle: "Morning Rally 2v2", venueName: "Quezon Convention Gym",
    gameDate: hours(-26), gameSport: "volleyball", includeResult: true,
    result: { sport: "volleyball", gameTitle: "Morning Rally 2v2", winnerTeamId: "A", scoreLine: "25–21, 25–19", teamA, teamB },
    media: momentMedia, caption: "Two straight sets with Edna 🏐 Thanks Thessa and Desiree for the battle!", tagged: [edna], actors: [],
    audience: "everyone", visibleTo: [], likeCount: 0, commentCount: 0, repostCount: 0, createdAt: hours(-20),
  });
  await db.doc(`posts/moments-morning-rally/likes/${thessa.id}`).set({ uid: thessa.id, createdAt: hours(-19) });
  await db.doc(`posts/moments-morning-rally/comments/c1`).set({ author: thessa, text: "Rematch next week? 😄", createdAt: hours(-19) });

  // ---- Presentation activity: Edna's own post, and the other 7 players interacting with it and the feed.
  let ednaMedia: { url: string; type: string }[] = [];
  if (!production) {
    const bucketName = "demo-huddl.appspot.com";
    const dest = `posts/${edna.id}/seed-edna-court.jpg`;
    const token = randomBytes(16).toString("hex");
    await getStorage().bucket(bucketName).upload(join(__dirname, "..", "seed-assets", "moment-court.jpg"), {
      destination: dest, metadata: { contentType: "image/jpeg", metadata: { firebaseStorageDownloadTokens: token } },
    });
    ednaMedia = [{ url: `http://127.0.0.1:9199/v0/b/${bucketName}/o/${encodeURIComponent(dest)}?alt=media&token=${token}`, type: "photo" }];
  }
  const ednaPost = "edna-moments-morning-rally";
  await db.doc(`posts/${ednaPost}`).set({
    author: edna, type: "postGame", gameId: "morning-rally", gameTitle: "Morning Rally 2v2", venueName: "Quezon Convention Gym",
    gameDate: hours(-26), gameSport: "volleyball", includeResult: false, media: ednaMedia,
    caption: "First HUDDL game in the books! 🏐 Thank you Bea, Thessa and Desiree for showing up and making it count. Who's in for Beach Volley Sunday?",
    tagged: [bea, thessa, desiree], actors: [], audience: "everyone", visibleTo: [],
    likeCount: 0, commentCount: 0, repostCount: 2, createdAt: hours(-3),
  });
  // Likes from all seven other players (the like trigger keeps likeCount in sync).
  const likers: [Ref, number][] = [[bea, -2.9], [thessa, -2.8], [desiree, -2.7], [roselle, -2.4], [kyle, -2.2], [jhon, -1.8], [althea, -1.5]];
  for (const [p, h] of likers) await db.doc(`posts/${ednaPost}/likes/${p.id}`).set({ uid: p.id, createdAt: hours(h) });
  // A short conversation (the comment trigger bumps commentCount and notifies Edna).
  const thread: [Ref, string, number][] = [
    [bea, "Best setter in Lucena 😤 Count me in for Sunday!", -2.85],
    [thessa, "Good game! We'll get you next time 💪", -2.75],
    [roselle, "Already applied to Beach Volley Sunday 🙋‍♀️", -2.3],
    [edna, "See you all on Sunday! Bring water, it gets hot at Dalahican ☀️", -2.1],
    [kyle, "Badminton crew might cross over to volleyball soon 👀", -1.9],
    [althea, "Love this! Come try billiards with us at 8-Ball Night 🎱", -1.4],
  ];
  for (const [i, [p, text, h]] of thread.entries()) {
    await db.doc(`posts/${ednaPost}/comments/c${i + 1}`).set({ author: p, text, createdAt: hours(h) });
  }
  for (const [p, h] of [[bea, -2.6], [roselle, -2.25]] as [Ref, number][]) {
    await db.doc(`posts/${ednaPost}/reposts/${p.id}`).set({ createdAt: hours(h) });
  }

  // Activity on the rest of the feed so every post looks alive.
  const likeAll = async (postId: string, people: Ref[]) => {
    for (const p of people) await db.doc(`posts/${postId}/likes/${p.id}`).set({ uid: p.id, createdAt: hours(-4) });
  };
  const comment = (postId: string, id: string, p: Ref, text: string, h: number) =>
    db.doc(`posts/${postId}/comments/${id}`).set({ author: p, text, createdAt: hours(h) });
  await likeAll("result-morning-rally", [bea, thessa, desiree, roselle, kyle]);
  await comment("result-morning-rally", "c1", desiree, "GG! That second set was close 😅", -22);
  await comment("result-morning-rally", "c2", bea, "Team A forever 🙌", -21.5);
  await likeAll("moments-morning-rally", [edna, desiree, althea]);
  await comment("moments-morning-rally", "c2", edna, "Anytime partner! 🏐", -18.5);
  await likeAll("hosting_sat-6v6-open", [edna, roselle, althea]);
  await comment("hosting_sat-6v6-open", "c1", desiree, "Saving a spot for my friend, applying soon!", -5);
  await likeAll("hosting_friday-doubles", [kyle, edna]);
  await comment("hosting_friday-doubles", "c1", kyle, "Partner up again? 🏸", -5.5);
  await likeAll("hosting_rapid-chess", [thessa, kyle]);
  await comment("hosting_rapid-chess", "c1", thessa, "Bringing my clock ♟️", -4.5);
  await likeAll("hosting_eight-ball-night", [desiree, jhon]);
  await likeAll("hosting_beach-volley", [bea, roselle, thessa, kyle]);
  await comment("hosting_beach-volley", "c1", thessa, "Is it beginner friendly?", -4.2);
  await comment("hosting_beach-volley", "c2", edna, "Yes! All levels welcome 😊", -4);
  await likeAll("hosting_badminton-clinic", [roselle]);

  // Like notifications for Edna (likes have no trigger notification; comments do).
  await db.doc(`notifications/${edna.id}/items/like_${ednaPost}`).set({
    type: "like", title: "Bea Anne Balmes and 6 others liked your post", body: "First HUDDL game in the books! 🏐",
    actor: bea, postId: ednaPost, read: false, resolved: false, createdAt: hours(-1.5),
  });
  await db.doc(`notifications/${edna.id}/items/repost_${ednaPost}`).set({
    type: "like", title: "Roselle Jean De Leon and Bea Anne Balmes reposted your post", body: "First HUDDL game in the books! 🏐",
    actor: roselle, postId: ednaPost, read: false, resolved: false, createdAt: hours(-2.25),
  });
  for (const t of [bea, thessa, desiree]) {
    await db.doc(`notifications/${t.id}/items/tag_${ednaPost}`).set({
      type: "comment", title: "Edna Alas-as tagged you", body: "In moments from Morning Rally 2v2",
      actor: edna, gameId: "morning-rally", postId: ednaPost, read: false, resolved: false, createdAt: hours(-3),
    });
  }

  // More conversations in Chat.
  const dm = async (a: Ref, b: Ref, msgs: [Ref, string, number][]) => {
    const id = `dm_${[a.id, b.id].sort().join("_")}`;
    await db.doc(`chats/${id}`).set({ type: "direct", title: "", memberIds: [a.id, b.id], members: [a, b], readOnly: false, updatedAt: FieldValue.serverTimestamp(), unread: {} });
    for (const [i, [s, text, h]] of msgs.entries()) {
      await db.doc(`chats/${id}/messages/m${i + 1}`).set({ senderId: s.id, senderName: s.name, text, system: false, createdAt: hours(h) });
    }
  };
  await dm(edna, roselle, [[roselle, "Hi Edna! I applied to Beach Volley Sunday 😊", -2], [roselle, "Can I bring my own ball?", -1.9]]);
  await dm(edna, kyle, [[kyle, "Nice post! Do you play badminton too?", -1.8], [edna, "A little! Maybe I'll join your Smash Session 🏸", -1.7], [kyle, "Let's go! Apply anytime", -1.6]]);
  const teamMsg = (gameId: string, id: string, s: Ref, text: string, h: number) =>
    db.doc(`chats/game_${gameId}/messages/${id}`).set({ senderId: s.id, senderName: s.name, text, system: false, createdAt: hours(h) });
  await teamMsg("morning-rally", "t1", bea, "See you at 7 AM! 🏐", -27);
  await teamMsg("morning-rally", "t2", thessa, "On my way!", -26.3);
  await teamMsg("morning-rally", "t3", edna, "GG everyone, thank you! 🙌", -24.5);
  await teamMsg("beach-volley", "t1", edna, "Welcome Bea! Sunday 6 AM at Dalahican ☀️", -3.5);
  await teamMsg("beach-volley", "t2", bea, "Can't wait! 🏐", -3.4);

  // Applications & invites to exercise host and player flows.
  await db.doc(`games/beach-volley/applications/${roselle.id}`).set({
    applicant: roselle, applicantId: roselle.id, teamId: "A", joinAs: "solo", groupMembers: [], note: "I can play the whole morning!",
    committed: true, status: "pending", via: "apply", createdAt: hours(-2), gameId: "beach-volley", gameTitle: "Beach Volley Sunday",
  });
  await db.doc(`games/beach-volley/applications/${jhon.id}`).set({
    applicant: jhon, applicantId: jhon.id, teamId: "B", joinAs: "solo", groupMembers: [], note: "First time trying volleyball 🙂",
    committed: true, status: "pending", via: "apply", createdAt: hours(-1), gameId: "beach-volley", gameTitle: "Beach Volley Sunday",
  });
  await db.doc(`games/sat-6v6-open/invites/${edna.id}`).set({
    invitee: edna, invitedBy: bea, teamId: "B", message: "We need a setter on Team B — join us?", status: "sent",
    createdAt: hours(-3), gameId: "sat-6v6-open", gameTitle: "Saturday 6v6 Open",
  });
  const n = (uid: string, id: string, d: Record<string, unknown>) =>
    db.doc(`notifications/${uid}/items/${id}`).set({ read: false, resolved: false, createdAt: FieldValue.serverTimestamp(), ...d });
  await n(edna.id, "invite_sat-6v6-open", { type: "invite", title: "Bea Anne Balmes invited you personally", body: "We need a setter on Team B — join us?", actor: bea, gameId: "sat-6v6-open", teamId: "B" });
  await n(edna.id, "applied_beach_r", { type: "applied", title: "Roselle Jean De Leon applied to your game", body: "Beach Volley Sunday · Solo · Team A", actor: roselle, gameId: "beach-volley" });
  await n(edna.id, "ended_morning-rally", { type: "ended", title: "Morning Rally 2v2 has ended. Share your photos and moments!", body: "Post your highlights for the community.", gameId: "morning-rally" });

  // A DM so Chat → Direct has content.
  const dmId = `dm_${[edna.id, bea.id].sort().join("_")}`;
  await db.doc(`chats/${dmId}`).set({ type: "direct", title: "", memberIds: [edna.id, bea.id], members: [edna, bea], readOnly: false, updatedAt: FieldValue.serverTimestamp(), unread: {} });
  await db.doc(`chats/${dmId}/messages/m1`).set({ senderId: bea.id, senderName: bea.name, text: "Saw your invite? We really need a setter 😅", system: false, createdAt: hours(-2.9) });

  writeFileSync(localPath, JSON.stringify(existing, null, 2));
  console.log(`Done. ${PLAYERS.length} accounts ready. Temporary sign-in details saved to ${localPath} (git-ignored).`);
  console.log("Note: give the scheduler-backed triggers a few seconds to create game chats and activity cards.");
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
