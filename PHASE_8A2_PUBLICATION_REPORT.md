# Phase 8A.2 — Publication report

Date: 2026-10-27.  
No live Supabase change, no credential rotation, no remote, and no push.  
Business logic, AI calls, navigation, and screen layout were not changed.

## 1. Copyright status

`LICENSE` is the standard MIT License. The conditions were not edited.

The copyright line is:

`Copyright (c) 2026 Zikuan Zhao`

Phase 8A.1 left the placeholder `[YOUR FULL LEGAL ENGLISH NAME]` because the name was not in the project. The line above was written into `LICENSE` after that report, at 22:47 local time. This pass did not invent it and did not change it. It is not the Supabase project label and it is not the sample username `Zikuan` by itself. Git has no `user.name` or `user.email`.

The owner is treating the original application code as theirs to license under that personal name. This pass cannot independently prove ownership of every file. Third-party fonts, the Flutter logo, user content, and generated images stay outside the MIT grant. See `ASSET_LICENSES.md`.

If that is not the owner's personal legal English name, correct `LICENSE` and amend this commit before any push.

## 2. Quotation catalog findings

`assets/data.json` has 26 theme groups and 104 quote entries. The JSON shape is unchanged: each quote still has `id`, `text`, `author`, and `theme`. Theme prompts have no author and were not treated as attributed quotations. They were left as they were.

| Class | Count | Result |
| --- | --- | --- |
| Verified public domain | 4 | Kept. Original Chinese, not a translation. |
| Explicitly licensed for redistribution | 0 | No license notice was found for any quoted passage. |
| Original project-authored text | 100 quotes, plus the unattributed theme prompts | The 100 quotes are new English prompts written for this release. Theme prompts were already unattributed and were not rewritten. |
| Unverified | 100, before replacement | Modern works, translations, or passages whose exact wording could not be tied to a public-domain source. Replaced. |

Public-domain entries kept, with the evidence used:

| Id | Attribution kept | Why it was kept |
| --- | --- | --- |
| `q_calli_01` | 孙过庭，《书谱》 | The sentence 一点成一字之规，一字乃终篇之准。 is in the Wikisource transcription of 书谱. Sun Guoting died in 688. |
| `q_calli_02` | 孙过庭，《书谱》 | 察之者尚精，拟之者贵似。 is in the same transcription. |
| `q_calli_03` | 刘熙载，《艺概》 | The words match the sentence in 书概. Liu Xizai died in 1881. *Yigai* was published in 1873. Wikisource marks the work public domain because the author died more than 100 years ago and it was published before 1931. Some editions differ in punctuation. |
| `q_calli_04` | 蔡邕，《笔论》 | Wikisource transcribes the opening 书者，散也。欲书，先散怀抱 and marks this Eastern Han text public domain. Cai Yong died in 192. The catalog omits one comma and ends before 任情恣性. |

Everything else in the quote list was unverified. Short length and presence on the public web were not treated as permission. No permission was invented. Those 100 texts and their personal attributions were replaced. `Catalog._parseQuotes` drops a quote whose author is empty, so the author field is the neutral label `Original prompt`.

The same kind of attributed sample text in `lib/community_post.dart` and `lib/mock_cloud.dart` was replaced. Those records are unused sample constants, not Supabase user content. A test fixture that labeled an original sentence as John Cage now says `Original prompt`. The stock Daily Inspiration line in `DailyPush.fallback` was already original and was not changed. Stored letters and model prompts were not changed.

## 3. Changes to public assets

- `assets/data.json` — 100 quote texts and authors replaced. Four calligraphy quotes, all theme entries, all ids, and the entry count stay. `Catalog.loadFromBundle` still accepts the file.
- `lib/community_post.dart`, `lib/mock_cloud.dart` — sample quotation fields only.
- `test/daily_discovery_layout_test.dart` — fixture attribution only.
- `README.md`, `ASSET_LICENSES.md`, `SUBMISSION_CHECKLIST.md`, `PHASE_8A_RELEASE_REPORT.md`, `PHASE_8A_FINAL_CHECK.md` — license and catalog notes brought in line with `LICENSE` and the catalog.
- `PHASE_8A2_PUBLICATION_REPORT.md` — this file.

`web/view.html` is not used by the Flutter app. It hardcodes the hosted project and a publishable client key. It was not deleted. `.gitignore` keeps it out of the public tree.

## 4. Secret scan result

`git check-ignore` excludes `.env.local`, `tool/`, `supabase/.temp/`, and `web/view.html`. None of those paths were in the dry run. Nothing was force-added.

After the temporary scanner was removed, `git add -n .` listed 182 files, before this report. The only name that needed a second look was `.env.example`, whose values are `replace-with-...` placeholders.

No service-role key, JWT, private key, judge mailbox, or hardcoded judge password was found in the proposed public set. Documentation files contain the words `sb_secret` and `sb_publishable` as descriptions, not secret values. `lib/main.dart` still has the client publishable key. That is expected for this client and is not a service-role key.

Ignored files on disk still hold local keys. They were not printed, deleted, or rotated.

`PHASE_8A_FINAL_CHECK.md` still contains the old placeholder sentence as a historical note. `LICENSE` does not.

## 5. Test results

Flutter 3.47.4, Dart 3.13.3.

`assets/data.json` parses as JSON. 104 quotes, 26 theme groups, 100 authors `Original prompt`, and the four calligraphy attributions above. Every quote has non-empty string `id`, `text`, `author`, and `theme`.

`flutter analyze`  
Exit code 1. Two existing infos at `lib/post_share_sheet.dart:127` for deprecated `Share` / `share`. No errors. No warnings.

`flutter test`  
Exit code 0. **50 tests passed.** Google Fonts failed to download during the run. Those errors did not fail the suite.

Local Markdown links in the release docs resolve to files on disk.

## 6. Git commit status

Local commit created on `main`. Message: `Initial public release of Inspiration Museum`.

The hash is `git rev-parse HEAD` after that commit. It is not pasted into this file, because writing the hash into the tree would change the commit. The chat report that accompanies this file states the hash.

Git had no author identity. The commit author name is the copyright name already in `LICENSE`. The author email is `local-only@localhost` because no real email was configured and one was not invented as a deliverable address. Change it with `git commit --amend` before the first push if a real email should be public. That amend was not done here.

No remote was added. Nothing was pushed.

## 7. Remaining publication blockers

None of the following block this local commit. They do block a careless public push:

1. Confirm `Zikuan Zhao` is the owner's personal legal English name. If it is not, edit `LICENSE` and amend the commit before pushing.
2. Set the Git author email to a real address before the first push, if `local-only@localhost` should not appear on GitHub.
3. Do not force-add `.env.local`, `tool/`, `supabase/.temp/`, or `web/view.html`.
4. If this folder was shared while `.env.local` or the old judge password was in it, rotate those credentials before the repository is public. Nothing was rotated here.
5. A clone cannot build the Supabase project from these migrations alone. That is documented in `DATABASE_REPRODUCIBILITY.md`. It does not block publishing the source.
6. Launcher icons are still the default Flutter logo. That is acceptable for a source repository and should be replaced before a store listing.

## 8. Next steps for the GitHub repository

Do these only after the owner approves a public repository.

1. Create an empty public repository named `inspiration-museum`.
2. Use this description: `An AI-powered space for daily inspiration, creative reflection, and unexpected discovery.`
3. Leave the license as MIT. The license file is already in the tree. Do not generate a second one.
4. From this directory:

```
git remote add origin <the new repository URL>
git push -u origin main
```

5. On GitHub, confirm the detected license is MIT and that `.env.local` is not in the file list.

This pass did not create the remote and did not push.
