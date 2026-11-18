/**
 * End-to-end backend smoke test against the running emulators (run after `npm run seed`).
 * Uses real Auth sign-ins and calls the callable functions + Firestore REST exactly as the app would.
 */
import { readFileSync } from "fs";
import { join } from "path";

const AUTH = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1";
const FN = "http://127.0.0.1:5001/demo-huddl/asia-southeast1";
const FS = "http://127.0.0.1:8080/v1/projects/demo-huddl/databases/(default)/documents";
const creds: Record<string, { email: string; password: string }> = JSON.parse(readFileSync(join(__dirname, "..", "seed-credentials.local.json"), "utf8"));

let passed = 0, failed = 0;
function check(name: string, ok: boolean, detail = "") {
  if (ok) { passed++; console.log(`  ✔ ${name}`); } else { failed++; console.log(`  ✘ ${name} ${detail}`); }
}

async function idToken(username: string): Promise<{ token: string; uid: string }> {
  const c = creds[username];
  const r = await fetch(`${AUTH}/accounts:signInWithPassword?key=demo`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email: c.email, password: c.password, returnSecureToken: true }) });
  const j = await r.json();
  return { token: j.idToken, uid: j.localId };
}

async function call(name: string, data: unknown, token?: string): Promise<{ ok: boolean; result?: any; message?: string }> {
  const r = await fetch(`${FN}/${name}`, { method: "POST", headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify({ data }) });
  const j: any = await r.json();
  return j.error ? { ok: false, message: j.error.message } : { ok: true, result: j.result };
}

async function getDoc(path: string, token: string) {
  const r = await fetch(`${FS}/${path}`, { headers: { Authorization: `Bearer ${token}` } });
  return { status: r.status, body: await r.json() as any };
}

async function patchDoc(path: string, fields: Record<string, unknown>, token: string) {
  const r = await fetch(`${FS}/${path}`, { method: "PATCH", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify({ fields }) });
  return r.status;
}

async function main() {
  console.log("Auth");
  const wrong = await call("signInWithUsername", { username: "ednaalas-as", password: "nope-nope" });
  check("username sign-in rejects a wrong password", !wrong.ok && wrong.message === "Wrong username or password", wrong.message);
  const right = await call("signInWithUsername", { username: "ednaalas-as", password: creds["ednaalas-as"].password });
  check("username sign-in returns a custom token", right.ok && typeof right.result?.token === "string");

  const edna = await idToken("ednaalas-as");
  const kyle = await idToken("kyleabandia");
  const thessa = await idToken("thessasurell");
  const bea = await idToken("beaannebalmes");

  console.log("Privacy rules");
  const uname = await getDoc("usernames/ednaalas-as", kyle.token);
  check("usernames doc holds no email", uname.status === 200 && !("email" in (uname.body.fields ?? {})));
  const stat = await patchDoc(`users/${kyle.uid}?updateMask.fieldPaths=stats`, { stats: { mapValue: { fields: { wins: { integerValue: "99" } } } } }, kyle.token);
  check("players cannot edit their own stats", stat === 403, String(stat));
  const other = await patchDoc(`users/${edna.uid}?updateMask.fieldPaths=displayName`, { displayName: { stringValue: "hacked" } }, kyle.token);
  check("players cannot edit someone else's profile", other === 403, String(other));
  const gameWrite = await patchDoc("games/friday-doubles?updateMask.fieldPaths=spotsLeft", { spotsLeft: { integerValue: "9" } }, kyle.token);
  check("clients cannot change rosters directly", gameWrite === 403, String(gameWrite));
  const apps = await getDoc(`games/beach-volley/applications/${(await idToken("roselledeleon")).uid}`, kyle.token);
  check("non-hosts cannot read others' applications", apps.status === 403, String(apps.status));

  console.log("Applying");
  const noCommit = await call("applyToGame", { gameId: "eight-ball-night", teamId: "B", joinAs: "solo", note: "", committed: false }, kyle.token);
  check("apply without commitment is refused", !noCommit.ok && /commitment/.test(noCommit.message ?? ""), noCommit.message);
  const tooBig = await call("applyToGame", { gameId: "friday-doubles", teamId: "B", joinAs: "group", groupMemberIds: [edna.uid, bea.uid], note: "", committed: true }, thessa.token);
  check("solo-only game rejects group applications", !tooBig.ok, tooBig.message);
  const full = await call("applyToGame", { gameId: "friday-doubles", teamId: "A", joinAs: "solo", note: "", committed: true }, thessa.token);
  check("full team is refused with the design's copy", !full.ok && /Team A is full\. Pick Team B to apply\./.test(full.message ?? ""), full.message);
  const ok = await call("applyToGame", { gameId: "friday-doubles", teamId: "B", joinAs: "solo", note: "Let's go!", committed: true }, thessa.token);
  check("valid application is accepted as pending", ok.ok, ok.message);
  const dup = await call("applyToGame", { gameId: "friday-doubles", teamId: "B", joinAs: "solo", note: "", committed: true }, thessa.token);
  check("duplicate application is refused", !dup.ok, dup.message);

  console.log("Hosting");
  const notHost = await call("acceptApplication", { gameId: "friday-doubles", applicantId: thessa.uid }, kyle.token);
  check("only the host can accept", !notHost.ok);
  const roselle = await idToken("roselledeleon");
  const accept = await call("acceptApplication", { gameId: "friday-doubles", applicantId: thessa.uid }, roselle.token);
  check("host accepts the applicant", accept.ok, accept.message);
  const g = await getDoc("games/friday-doubles", roselle.token);
  const memberIds = (g.body.fields.memberIds.arrayValue.values ?? []).map((v: any) => v.stringValue);
  check("accepted player is on the roster", memberIds.includes(thessa.uid));
  const chat = await getDoc("chats/game_friday-doubles", thessa.token);
  check("accepted player can read the team chat", chat.status === 200, String(chat.status));
  const notif = await getDoc(`notifications/${thessa.uid}/items`, thessa.token);
  check("applicant got an 'accepted' notification", JSON.stringify(notif.body).includes("accepted"));

  console.log("Invites & leaving");
  const inv = await call("invitePlayer", { gameId: "eight-ball-night", inviteeId: edna.uid, teamId: "B", message: "Join us!" }, (await idToken("altheaaringo")).token);
  check("host can invite a player", inv.ok, inv.message);
  const inv2 = await call("invitePlayer", { gameId: "eight-ball-night", inviteeId: edna.uid, teamId: "B", message: "" }, (await idToken("altheaaringo")).token);
  check("duplicate invite shows 'already has an invite'", !inv2.ok && /already has an invite/.test(inv2.message ?? ""), inv2.message);
  const acc = await call("respondInvite", { gameId: "eight-ball-night", accept: true }, edna.token);
  check("invitee accepts and joins the team", acc.ok && acc.result?.teamId === "B", acc.message);
  const leave = await call("leaveGame", { gameId: "eight-ball-night" }, edna.token);
  check("player can leave before the start", leave.ok, leave.message);

  console.log("Feed & posts");
  const post = await call("createPost", { gameId: "morning-rally", caption: "", media: [], taggedIds: [], includeResult: true, audience: "everyone" }, edna.token);
  check("empty post is refused with the design's copy", !post.ok && post.message === "Add a photo, video or caption to post", post.message);
  const badTag = await call("createPost", { gameId: "morning-rally", caption: "GG", media: [], taggedIds: [kyle.uid], includeResult: true, audience: "everyone" }, edna.token);
  check("tags limited to players from that game", !badTag.ok, badTag.message);
  const goodPost = await call("createPost", { gameId: "morning-rally", caption: "What a rally!", media: [], taggedIds: [bea.uid], includeResult: true, audience: "everyone" }, edna.token);
  check("moments post is created", goodPost.ok && !!goodPost.result?.postId, goodPost.message);
  const onlyMe = await call("createPost", { gameId: "morning-rally", caption: "Private note", media: [], taggedIds: [], includeResult: false, audience: "onlyMe" }, edna.token);
  const hidden = await getDoc(`posts/${onlyMe.result?.postId}`, kyle.token);
  check("'Only me' posts are hidden from others", hidden.status === 403, String(hidden.status));

  console.log("Chat & blocks");
  const dm = await call("openDirectChat", { otherId: kyle.uid }, edna.token);
  check("DM thread opens", dm.ok && /^dm_/.test(dm.result?.chatId ?? ""), dm.message);
  const outsider = await getDoc(`chats/${dm.result?.chatId}`, thessa.token);
  check("non-members cannot read a DM", outsider.status === 403, String(outsider.status));

  console.log("Collection-group queries used by the app");
  const cg = async (coll: string, field: string, value: string, token: string) => {
    const r = await fetch(`${FS.replace(/\/documents$/, "")}/documents:runQuery`, {
      method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ structuredQuery: { from: [{ collectionId: coll, allDescendants: true }],
        where: { fieldFilter: { field: { fieldPath: field }, op: "EQUAL", value: { stringValue: value } } } } }),
    });
    const j: any = await r.json();
    return { ok: r.status === 200 && !j[0]?.error, count: Array.isArray(j) ? j.filter((x: any) => x.document).length : 0 };
  };
  const myApps = await cg("applications", "applicantId", thessa.uid, thessa.token);
  check("player can list their own applications (PENDING chips)", myApps.ok && myApps.count >= 1, JSON.stringify(myApps));
  const spyApps = await cg("applications", "applicantId", thessa.uid, kyle.token);
  check("others cannot list someone else's applications", !spyApps.ok);
  await fetch(`${FS}/posts/moments-morning-rally/likes/${kyle.uid}`, { method: "PATCH", headers: { Authorization: `Bearer ${kyle.token}`, "Content-Type": "application/json" }, body: JSON.stringify({ fields: { uid: { stringValue: kyle.uid } } }) });
  const myLikes = await cg("likes", "uid", kyle.uid, kyle.token);
  check("player can list their own likes (heart stays filled)", myLikes.ok && myLikes.count >= 1, JSON.stringify(myLikes));
  const myInv = await cg("invites", "invitee.id", edna.uid, edna.token);
  check("invitee can list their own invites (INVITED YOU chips)", myInv.ok, JSON.stringify(myInv));

  const blockedList = await getDoc(`users/${edna.uid}/blocked`, edna.token);
  check("player can list their own block list", blockedList.status === 200, String(blockedList.status));
  const otherBlocked = await getDoc(`users/${edna.uid}/blocked`, kyle.token);
  check("others cannot read someone's block list", otherBlocked.status === 403, String(otherBlocked.status));

  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
