# Phase 8A — Release report

Date: 2026-10-27.  
Tree: the Inspiration Museum working copy.  
No business logic was changed. No Edge Function was deployed. No model was called. No credential was rotated or printed. Nothing was pushed to GitHub. No commit was created.

## 1. Files created and modified

Created:

- `LICENSE`
- `ASSET_LICENSES.md`
- `ARCHITECTURE.md`
- `DEMO_ACCESS.md`
- `SUBMISSION_CHECKLIST.md`
- `PHASE_8A_RELEASE_REPORT.md`
- `.env.example`

Replaced:

- `README.md` (the Flutter stub is gone)

Modified:

- `.gitignore` now ignores `supabase/.temp/`, the whole `tool/` directory, `*.dump`, and `*.bak`. Existing rules for `.env`, `.env.*`, and `!.env.example` stay.

Not modified:

- Flutter application code, tests, Edge Functions, SQL migrations, and `pubspec.yaml`.
- `pubspec.yaml` still says `A new Flutter project.` That string was left alone.

Sensitive files were not deleted. `.env.local` and `tool/` are still on disk and are ignored by git.

## 2. Git readiness

This directory was not a Git repository. `git init` was run here only. There is no commit, no branch history, and no remote.

`git add -n` would add 180 files. A dry run did not include `.env.local`, `tool/`, or `supabase/.temp/`. `git check-ignore` confirms those paths are ignored. `.env.example`, `LICENSE`, and the new docs would be added.

The repository root is this application directory. Sibling copies elsewhere on the desktop are outside this `.git` and would not be committed.

Recommended next steps, for the owner, after the copyright line is filled and the file list is reviewed:

```bash
git status
git add -n .
git add .
git status
git commit
```

Do not add `.env.local` or `tool/` with `git add -f`. Do not create the GitHub remote or push until the items in section 9 are accepted.

## 3. MIT License status

`LICENSE` is the standard MIT License text. The conditions were not edited.

Copyright year: 2026.  
Copyright holder: `Zikuan Zhao`. The line is a personal name, not an organization. A Supabase project display name was not used. See `PHASE_8A2_PUBLICATION_REPORT.md` for the later check.

## 4. Asset licensing findings

Recorded in `ASSET_LICENSES.md`.

- The in-app mark is a `CustomPainter` in `lib/brand/museum_brand.dart`. There is no separate logo bitmap. The name and the mark are not described as MIT trademarks. No registration was found.
- `assets/fonts/NotoSerifSC-Museum.ttf` is about 5 KB. Source comments call it a Noto Serif SC subset, and the binary contains the vendor id `GOOG`. The SIL Open Font License text is not in the tree. Unresolved.
- DM Serif Display and Inter are loaded at runtime by `google_fonts`. They are not vendored.
- `assets/data.json` is a bundled theme catalog with no third-party notice. The owner must confirm the right to publish it.
- Generated images and user uploads are stored in Supabase, not in git. The MIT License does not cover them.
- Launcher and splash bitmaps were not re-licensed in this pass.
- Package licenses were not copied out one by one.

## 5. Security findings

A scan reported file paths and rule names only.

| Path | Result |
| --- | --- |
| `.env.local` | Contains assignments for a Nebius key, a fal key, and a Supabase access token. Gitignored. Not deleted. |
| `tool/` | Many scripts match JWT, bearer, access-token, or password patterns, including seed and deploy helpers. The whole directory is gitignored. Not deleted. |
| `lib/judge_demo.dart` | Email and password come from empty `String.fromEnvironment` values. No demo password remains in source. |
| `lib/main.dart` | Holds the project URL and a key whose prefix is `sb_publishable_`. The app passes it as `publishableKey`. It is not an `sb_secret_` key. Left in place. |
| `web/view.html` | Unreferenced static page. It contains a publishable key, not a service-role key. It would be included in the first commit unless the owner removes it. |
| SQL `service_role` grants | Postgres role grants in migrations, not a secret key. |
| `PHASE_7B_VERIFICATION.md` | Mentions the string `sb_secret` as a scan result. It does not contain a secret value. |

No service-role key was found in Dart or TypeScript. History before `git init` cannot be searched, because there was none. If this folder was copied while `.env.local` or the old judge password existed, rotate those credentials before the tree is published. This phase did not rotate them.

## 6. Documentation completed

| Document | Role |
| --- | --- |
| `README.md` | Product, AI roles, next-day letters, stack, setup, limitations, license |
| `ARCHITECTURE.md` | Client, Supabase, the three functions, Nano, Ultra, FLUX, caching, ranking, fallbacks, secrets |
| `DEMO_ACCESS.md` | Judge access without a password or a fake URL |
| `ASSET_LICENSES.md` | Third-party and branding boundaries |
| `SUBMISSION_CHECKLIST.md` | Only verified items are checked |
| `LICENSE` | MIT terms, placeholder holder |
| `.env.example` | Placeholder names. The Flutter app does not read this file. |

Setup instructions match the tree: Dart `^3.13.3`, `flutter pub get`, `lib/main.dart` for the client key, function secrets `NEBIUS_API_KEY` and `FAL_KEY`, and the migrations that actually exist. The README states that those migrations are not a full database bootstrap and that `get_random_daily_letter` is not defined here.

Local links among the new docs resolve to files on disk.

## 7. Remaining submission requirements

Still open, from `SUBMISSION_CHECKLIST.md`:

- Public GitHub repository and the first commit
- Copyright holder filled in
- Proof of the Nemotron Nano license, and a decision not to rely on Ultra alone
- Hosted demo or test build, YouTube video under three minutes, Devpost text
- Model and infrastructure feedback sent to the organizers
- A demo account that stays usable through judging, with today's letter already prepared
- Confirmation that hackathon work can be shown without git history from before this initialization

## 8. Tests executed and results

Commands were run from a substituted drive so the analyzer could read this path. Flutter 3.47.4, Dart 3.13.3.

`flutter analyze`  
Exit code 1. Two infos, both existing, both at `lib/post_share_sheet.dart:127` for deprecated `Share` / `share`. No errors. No warnings. Those infos were not changed.

`flutter test`  
Exit code 0. **50 tests passed.**

Google Fonts raised load errors for Inter and DM Serif Display during the run. The suite still passed. Those messages are the existing test behavior when the font host is unreachable.

No Edge Function tests were run. Deno was not run. No iOS or Android build was run. No live inference was run.

## 9. Items requiring project-owner approval before publication

1. The copyright line is now `Copyright (c) 2026 Zikuan Zhao`. See `PHASE_8A2_PUBLICATION_REPORT.md`.
2. Unverified quotations in `assets/data.json` were replaced. Four public-domain calligraphy sentences remain. The Noto subset notice is `assets/fonts/OFL-NotoSerifSC.txt`.
3. Decide whether `web/view.html` stays in the public tree.
4. Review `git status` before the first commit. Do not force-add ignored files.
5. Rotate the Nebius key, the fal key, the Supabase access token, and the old judge password if this folder or the old source was shared. Do not put the new password back into source.
6. Point a public fork at its own Supabase project, or accept that `lib/main.dart` currently contains this project's publishable client key.
7. Create the GitHub repository and push only after the steps above. This phase did not do that.
8. Prepare the demo account's letter for the recording day, and leave the Home REFRESH control untapped.
9. Publish a demo URL, a test build, and a YouTube video only when they exist. The docs use placeholders on purpose.
10. `pubspec.yaml` description has been replaced with a short product description.
