# HUDDL Midterm — Things to do before you submit

## Must do
- [ ] **Read and personalize the reflection (section 6).** It's written from the verifiable project history. Change anything that doesn't sound like you. If you wrote or edited any code yourself, add one or two sentences naming those parts. Don't claim more than you did.
- [ ] **Check your course's AI-use policy.** The reflection openly says an AI coding assistant wrote most of the code under your direction. If the policy asks for a specific disclosure format, follow it.
- [x] **Cover page filled in:** Edna D. Alas-as · CSSE105: Mobile Application Development · Dean Rodrigo C. Belleza.
- [ ] **Open the three links from the PDF** (cover and section 2) to confirm they work for you:
  - FIGMA FILE: https://www.figma.com/design/kqWMa2AGXpp267HtbmbXY8/HUDDL. In Figma → Share, make sure your instructor can view it ("Anyone with the link can view", or invite them).
  - FIGMA PREVIEW: https://www.figma.com/proto/kqWMa2AGXpp267HtbmbXY8/HUDDL?node-id=2-2 (plays the prototype from the Splash screen)
  - GitHub: https://github.com/ednaalas-as/HUDDL (public)

## Figma prototype: verified complete, nothing to do
- **Connections fixed on Nov 18, 2026:** 19 base screens (Sign Up, Sign In, Home, Discover, Chat, Profile, …) were inside a hidden group, so links to them, such as onboarding 3's **Get Started**, did nothing. The group is still hidden and unchanged. Visible copies now sit in a new **BASE SCREENS** section, and 643 links point to them. Audit now: 220 playable frames, 1,648 links, 0 links to hidden frames. Only the Splash screen has no incoming link, because it's where the flows start.
- Optional: export 4–6 frames from Figma (select a frame → Export → PNG) to add as figures in section 2. Figma's export service returned blank images for this file, so the PDF uses the link only.

## Good to know before presenting
- The app runs on the **Firebase Emulator Suite**. Start it with `firebase/emulators.sh` and re-seed before demoing (see `docs/presentation/HUDDL_PRESENTATION_GUIDE.md`).
- Coverage numbers, in case someone asks: Figma 100%, SwiftUI interface 97%, **functionality verified 60%**, functionality implemented 96%.
- The public repo includes the full names of your eight test players (in the seed script, docs and screenshots). They're placeholders you chose; if any of them prefers not to be named publicly, Claude can replace the names.
- Never share `docs/presentation/HUDDL_ACCOUNTS_PRIVATE.md` or `firebase/functions/seed-credentials.local.json`. They aren't in the repo.
