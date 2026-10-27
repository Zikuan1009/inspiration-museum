# Phase 8A.1 — Final check

This note records the tree at the end of Phase 8A.1. `PHASE_8A2_PUBLICATION_REPORT.md` is the later publication check. `LICENSE` now reads `Copyright (c) 2026 Zikuan Zhao`. The placeholder sentences below describe the earlier state.

Date: 2026-10-27.  
No business logic, navigation, or screen layout was changed. The live Supabase project was not queried or modified. Nothing was committed or pushed. No credential was printed or rotated.

## 1. Files modified

- `LICENSE` — copyright line now reads `Copyright (c) 2026 [YOUR FULL LEGAL ENGLISH NAME]`. The MIT conditions are unchanged.
- `lib/judge_demo.dart` — the test-account email and password are no longer in source. The entrance still exists and stays hidden unless a local build passes `JUDGE_EMAIL` and `JUDGE_PASSWORD`.
- `README.md` — the opening now names the filter bubble, serendipity, and the step from reading a discovery to making a Collection. Setup and limitations were kept.
- `ASSET_LICENSES.md`, `SUBMISSION_CHECKLIST.md`, `PHASE_8A_RELEASE_REPORT.md` — copyright placeholder wording updated so it matches `LICENSE`.
- `PHASE_8A_FINAL_CHECK.md` — this report.

Already in place from the previous preparation, and rechecked here:

- `assets/fonts/OFL-NotoSerifSC.txt`
- `DATABASE_REPRODUCIBILITY.md`
- `pubspec.yaml` description
- `.gitignore` rules for `.env.local`, `tool/`, `supabase/.temp/`, and `web/view.html`

## 2. MIT copyright status

The license text is the standard MIT License.

The owner confirmed that the copyright holder should be their personal legal English name, not a team, organization, project name, or account username. That exact name is not written in the project, so it was not guessed. The line is still:

`Copyright (c) 2026 [YOUR FULL LEGAL ENGLISH NAME]`

That placeholder must be replaced by hand before publication. Until then the copyright declaration is not final.

The owner is treating the original application code as theirs to license. This pass cannot independently prove ownership of every file. Third-party fonts, the Flutter logo, quoted catalog text, user content, and generated images are outside that grant. See `ASSET_LICENSES.md`.

## 3. Licensing issues resolved

| Item | Result |
| --- | --- |
| Noto Serif SC subset | Confirmed from the font name table: family `Noto Serif SC SemiBold`, copyright `(c) 2017-2024 Adobe (http://www.adobe.com/).`, license URL `https://openfontlicense.org`. The SIL Open Font License 1.1 text is in `assets/fonts/OFL-NotoSerifSC.txt`. The file is a small subset. No Reserved Font Name is stated in the name table. |
| `assets/data.json` | Still unresolved. It is a bundled catalog of theme words and attributed quotations. Rights to those quotations were not established. |
| Launcher, web, and Windows icons | The inspected PNGs are the default Flutter logo, a Google brand, not the museum mark. They may stay as the unmodified Flutter template. They are not MIT-licensed project art. |
| iOS launch images | Blank template placeholders. |
| Brand | The name and the painter mark are not described as a registered trademark. No registration was found. |
| `web/view.html` | Not used by the Flutter app. It is a static viewer that hardcodes the hosted project and a publishable client key. It was not deleted. It is gitignored so it is not in the proposed public tree. |

## 4. Security scan results

`git check-ignore` excludes `.env.local`, `tool/` (probes, seeds, deploy scripts, and dumps), `supabase/.temp/`, and `web/view.html`.

After removing the temporary scanner, `git add -n` would add 182 files. None of those excluded paths were in the dry run.

Hits inside files that would be tracked, by rule name only:

| File | Rule | Meaning |
| --- | --- | --- |
| `lib/main.dart` | `sb_publishable` | The client publishable key. Expected. Not a service-role key. |
| `.env.example`, `README.md` | placeholder secret-name assignments | Values are `replace-with-...`. Not real keys. |
| Architecture and phase notes | the words `sb_secret` or `sb_publishable` | Descriptions of the scan. No secret value. |

No service-role key, JWT, private key, judge password, or demo mailbox was found in the proposed public set. The judge password had been put back into `lib/judge_demo.dart` for a local demo. It has been removed from source again so it will not be committed. The process already serving http://127.0.0.1:8671 was not restarted, so that running build can still contain the previous compile until the next restart.

Ignored files on disk still hold local keys. They were not deleted and not rotated.

## 5. Database reproducibility status

A fresh Supabase project cannot be created from this repository. The migrations add letter, signal, rank, and draft objects only. They assume `profiles` already exists. The client does not insert a profile or generate `app_id`. `get_random_daily_letter`, theme seed data, and storage policies are not in the tree.

No guessed migration was written, and the live database was not changed. The missing pieces and their effect on a new install are in `DATABASE_REPRODUCIBILITY.md`. This does not block publishing the source. It does block a stranger from bootstrapping the backend with `supabase db push` alone.

## 6. Tests and analyzer results

Flutter 3.47.4, Dart 3.13.3.

`flutter analyze`  
Exit code 1. Two existing infos at `lib/post_share_sheet.dart:127` for deprecated `Share` / `share`. No errors. No warnings.

`flutter test`  
Exit code 0. **50 tests passed.** Google Fonts failed to download during the run. Those errors did not fail the suite.

Local Markdown links in the release docs resolve to files on disk.

## 7. Remaining blockers before public GitHub publication

1. Replace `[YOUR FULL LEGAL ENGLISH NAME]` in `LICENSE` with the owner's personal legal English name. Do not publish while the placeholder is still there.
2. Decide whether `assets/data.json` may be published with its attributed quotations. The app loads that file, so removing it requires a matching code change, which was not made here.
3. Review `git status` before the first commit. Do not force-add `.env.local`, `tool/`, `supabase/.temp/`, or `web/view.html`.
4. If this folder was shared while `.env.local` or the judge password was in it, rotate those credentials before the repository is public. Nothing was rotated in this pass.

Not blockers for the source commit: a public demo URL, a YouTube video, Devpost text, a cited Nemotron Nano license page, replacing the Flutter launcher icons, and a schema-only database export.

No commit was created. No GitHub repository was created. Nothing was pushed.
