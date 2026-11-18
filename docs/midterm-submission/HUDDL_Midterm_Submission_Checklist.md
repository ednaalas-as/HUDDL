# HUDDL Midterm — Things to do before you submit

## Must do
- [ ] **Read the reflection (section 6) once more.** It now says you wrote almost half of the code, and that the assistant continued it and revised most of it under your direction. If you can, add a sentence naming which parts you wrote yourself (for example, specific screens).
- [ ] **Check your course's AI-use policy.** The reflection openly says you wrote almost half of the code and an AI coding assistant continued and revised it under your direction. If the policy asks for a specific disclosure format, follow it.
- [x] **Cover page filled in:** Edna D. Alas-as · CSSE105: Mobile Application Development · Dean Rodrigo C. Belleza.
- [ ] **Open the three links from the PDF** (cover and section 2) to confirm they work for you:
  - FIGMA DESIGN LINK: https://www.figma.com/design/kqWMa2AGXpp267HtbmbXY8/HUDDL?node-id=336-1626&t=v8gXf6gIJC83mmb6-1 In Figma → Share, make sure your instructor can view it ("Anyone with the link can view", or invite them).
  - FIGMA PROTOTYPE LINK: https://www.figma.com/proto/kqWMa2AGXpp267HtbmbXY8/HUDDL?node-id=305-714&t=Ro4JCO5iI4iX0zSc-1&scaling=scale-down&content-scaling=fixed&page-id=0%3A1&starting-point-node-id=2%3A2&show-proto-sidebar=1 (opens on onboarding screen 1, with the flow list beside it)
  - GitHub: https://github.com/ednaalas-as/HUDDL (public)

## Figma prototype: verified complete, nothing to do
- **Connections fixed on Nov 18, 2026:** 19 base screens (Sign Up, Sign In, Home, Discover, Chat, Profile, …) were inside a hidden group, so links to them, such as onboarding 3's **Get Started**, did nothing. The group is still hidden and unchanged. Visible copies now sit in a new **BASE SCREENS** section, and 643 links point to them. Audit now: 220 playable frames, 1,648 links, 0 links to hidden frames. Only the Splash screen has no incoming link, because it's where the flows start.
- Optional: export 4–6 frames from Figma (select a frame → Export → PNG) to add as figures in section 2. Figma's export service returned blank images for this file, so the PDF uses the link only.

## Good to know before presenting
- The app runs on the **Firebase Emulator Suite**. Start it with `firebase/emulators.sh` and re-seed before demoing (see `docs/presentation/HUDDL_PRESENTATION_GUIDE.md`).
- Coverage numbers, in case someone asks: Figma 100%, SwiftUI interface 97%, **functionality verified 60%**, functionality implemented 96%.
- The public repo includes the full names of your eight test players (in the seed script, docs and screenshots). They're placeholders you chose; if any of them prefers not to be named publicly, Claude can replace the names.
- Never share `docs/presentation/HUDDL_ACCOUNTS_PRIVATE.md` or `firebase/functions/seed-credentials.local.json`. They aren't in the repo.
