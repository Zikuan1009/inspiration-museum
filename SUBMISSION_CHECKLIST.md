# Submission checklist

Track: Best Apps and Agents, Nebius x NVIDIA Global AI Hackathon.  
Deadline: 30 October 2026.  
Checked against this working tree on 2026-10-27.  
A box is checked only when this tree already satisfies it. Everything else is still open.

## Product and track

- [ ] Submitted to the Best Apps and Agents track. The application is built for that track. Nothing has been submitted.
- [ ] Working application available to judges. The Flutter client, Supabase functions, and tests are in this tree. No public demo URL or downloadable build is published. iOS and Android release builds were not run.
- [x] Nebius Token Factory is integrated in source. `curate-card`, `prepare-letter`, and `rank-feed` call Token Factory chat completions. On 2026-10-27 the deployed bundles matched this source. See [PHASE_7B_VERIFICATION.md](PHASE_7B_VERIFICATION.md). This documentation pass did not repeat a live model call.
- [ ] NVIDIA open-source model requirement closed. Nemotron Nano (`nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B`) does real product work. The model card and license are not stored in this repository, so "open source" is not marked complete.
- [ ] Nemotron Ultra is not used as the sole open-model proof. Its id is `nvidia/Nemotron-3-Ultra-550b-a55b`. Whether those weights are open is unverified here.

## Repository and license

- [ ] Public GitHub repository. Git is initialized locally. There is no commit and no remote. Nothing was pushed.
- [x] MIT License ready to publish. [LICENSE](LICENSE) uses the standard MIT terms. The copyright line is `Copyright (c) 2026 Zikuan Zhao`.
- [x] English README with setup. [README.md](README.md).
- [x] Architecture documentation. [ARCHITECTURE.md](ARCHITECTURE.md).
- [x] Third-party licensing review written. [ASSET_LICENSES.md](ASSET_LICENSES.md). The Noto subset has an OFL notice taken from the font's own name table. Unverified catalog quotations were replaced with original prompts. Four public-domain calligraphy sentences remain. The Flutter launcher logo is still the template icon.
- [x] Secret scan of this tree completed, without printing secret values. `.env.local` and `tool/` are gitignored. See [PHASE_8A_RELEASE_REPORT.md](PHASE_8A_RELEASE_REPORT.md).

## Demo and submission materials

- [ ] Working public demo or test build. Local run instructions are in [DEMO_ACCESS.md](DEMO_ACCESS.md). No hosted URL is recorded.
- [x] English project description in the repository. The README is that description. It has not been pasted into Devpost.
- [ ] Public YouTube demonstration under three minutes. No video link is in the tree.
- [ ] Model and infrastructure feedback submitted to the organizers. Not written as a submission.
- [ ] Evidence that the work was done during the hackathon period. This directory had no git history before initialization, and no commit exists yet.
- [ ] Test access guaranteed through judging. The demo password is not in source. A private judge channel, a live Supabase project, and working function secrets still have to be confirmed by the owner.

## Local verification in this phase

- [x] `flutter analyze` run. Flutter 3.47.4, Dart 3.13.3. Exit code 1 because two existing infos are counted, both in `lib/post_share_sheet.dart` (`Share.share` is deprecated). No errors and no warnings.
- [x] `flutter test` run. Exit code 0. 50 tests passed. Google Fonts failed to download during the run. Those errors are caught by the existing tests and did not fail the suite.
- [x] Markdown links in the new docs point at local files that exist: `README.md`, `ARCHITECTURE.md`, `DEMO_ACCESS.md`, `ASSET_LICENSES.md`, `LICENSE`, and `PHASE_7B_VERIFICATION.md`.

## Do not mark these done yet

- Live Nano, Ultra, or FLUX success in this phase.
- A complete database bootstrap. Migrations do not recreate the original social schema, storage policies, or `get_random_daily_letter`.
- Native mobile build success.
- Credential rotation. Recommended before publication if this folder was shared. Not performed.
