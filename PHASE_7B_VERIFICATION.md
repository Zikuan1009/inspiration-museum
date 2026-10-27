# Phase 7B — Verification

Date: 2026-10-27.  
Tree: `灵感博物馆-新界面`.  
No remote function was deployed. No paid model call was made. No credential was rotated. No public repository was created.

Status words:

- **VERIFIED LIVE** — a real network call succeeded in this phase. None of the AI calls below have this status.
- **VERIFIED BY TEST** — a local automated test exercised the behavior with a fake or a pure function.
- **VERIFIED IN SOURCE ONLY** — read from the current source, and where noted, compared with the downloaded deployed bundle.
- **FAILED** — a check was run and did not pass.
- **UNVERIFIED** — not run, or not visible from this tree.

---

## 1. Deployed-function verification

The linked project ref in `supabase/.temp/linked-project.json` matches `project_id` in `supabase/config.toml` and the host in `lib/main.dart`. The local deploy scripts call the same ref. CLI v2.120.0 was not upgraded.

`supabase functions list` on 2026-10-27:

| Function | Status | Version | `verify_jwt` | Remote update (UTC) |
| --- | --- | --- | --- | --- |
| `curate-card` | ACTIVE | 13 | true | 2026-10-27 12:50:04 |
| `prepare-letter` | ACTIVE | 11 | true | 2026-10-25 17:34:57 |
| `rank-feed` | ACTIVE | 1 | true | 2026-10-24 15:16:57 |

The three bundles were downloaded into a temporary folder, not into this tree, and compared with the local `index.ts` files. SHA-256 and normalized text were equal for all three. The temporary copy was deleted.

That comparison is a source match. It is not a live inference.

| Question | Status |
| --- | --- |
| Functions exist on the intended project | VERIFIED LIVE for the list and the download. The list call hit Supabase, not Nebius or fal. |
| Deployed source matches this tree | VERIFIED IN SOURCE ONLY, by byte comparison of the download. Not a runtime generation. |
| A model call through the deployed function succeeds now | UNVERIFIED |

---

## 2. Generate Image workflow

Path, from source:

`InspirationEditorScreen._curate` (`deep: false`) → `CurationService.curate` → Edge Function `curate-card` → Nemotron Nano → optional Ultra → FLUX Schnell when `FAL_KEY` and an image brief exist → JPEG upload to `post_images/{userId}/{uuid}.jpg` → `image_url` → `_generatedImageUrl` → `_NetworkVisual` → `createPost(imageUrl:)` or `attachUploadedImage` when editing.

The deployed `curate-card` bundle matches this source, including the lenient JSON parser.

| Step | Status |
| --- | --- |
| Generate button calls the handler with `deep: false` | VERIFIED BY TEST |
| Loading copy, then a preview when a URL returns | VERIFIED BY TEST |
| Empty writing does not call the handler | VERIFIED BY TEST |
| A thrown curation error shows Try Again | VERIFIED BY TEST |
| Text can succeed while `image_error` is shown and no URL is stored | VERIFIED BY TEST |
| Publish request keeps the generated http URL, and appends an Ultra caption under the quote | VERIFIED BY TEST |
| Publish does not invent a URL when painting fails | VERIFIED BY TEST |
| Parser drops a non-http `image_url` and rejects a body with no keywords or quote | VERIFIED BY TEST |
| Nano returns structured JSON, FLUX returns bytes, storage accepts the JPEG, the URL loads, and the published collection shows that image | UNVERIFIED |

No live `curate-card` call was made in this phase. An older `tool/probe_out.txt` is not treated as a new result.

---

## 3. Daily Inspiration personalization

Next-day preparation was left as it is. Opening the card still does not call a model. No “generate today” button was added.

`prepare-letter` puts the portrait fields into the Nano prompt through `readProfile` and `personOf`: username, bio, age, gender, location, school, hobbies, personality, occupation. The prompt says not to invent missing facts. Likes, saves, and reflections become `interest_signals`. A changed interest stamp can refresh `observed_note`. That note is not shown in the UI. A profile save or a new signal deletes tomorrow’s `daily_letters` row and calls `prepareUpcomingLetter`. Today’s open card is not rewritten.

`useBreakout` is a hash of user id and date against `breakout_ratio` (default 30 when the value is missing). Under that threshold the function stores a catalog letter from `get_random_daily_letter` and skips Nano. The response field `source` is `"breakout"`. The stored row sets `forms` to `["breakout"]` and `why_today` to empty. The client does not read `forms`, so the open card cannot tell a catalog letter from a Nano letter.

`fetchDailyPush` still reads, in order: local cache for today, account metadata for today, `daily_letters` for today, then the catalog RPC, then `DailyPush.fallback`. The stock prompt is not written back. Cache, metadata, a prepared row, and a catalog row are. `resolveDailyLetter` encodes that order.

| Check | Status |
| --- | --- |
| Profile fields are in the generation prompt | VERIFIED IN SOURCE ONLY |
| Behavioral signals can change a later letter | VERIFIED IN SOURCE ONLY |
| A prepared row is what the card reads | VERIFIED IN SOURCE ONLY for the query. The choice order is VERIFIED BY TEST |
| Same-day cache is reused and wins over a newer prepared row | VERIFIED BY TEST |
| Empty or failed catalog becomes the stock prompt | VERIFIED BY TEST |
| Breakout skips Nano and stores a catalog letter | VERIFIED IN SOURCE ONLY |
| Stock prompt is not labeled as today’s prepared discovery | VERIFIED BY TEST. The card and the full page say `STARTING PROMPT` |
| A catalog letter is not labeled “personalized AI” | VERIFIED IN SOURCE ONLY. Both catalog and Nano letters use the feature name “Daily Inspiration”. The UI never says the card is a verified personalized recommendation |
| This account already has a personalized row for today | UNVERIFIED. The database was not queried |

### Demo preparation, not implemented

Use the existing signed-in pipeline. Do not insert a row by hand.

1. Sign in with the normal email form. The judge button is hidden unless the process is started with `JUDGE_EMAIL` and `JUDGE_PASSWORD` dart-defines. Do not commit those values.
2. If this demo day must not be a catalog letter, set that account’s breakout ratio to 0 in Backstage before the letter is prepared. Saving there already refreshes tomorrow, not the open card.
3. Preferred path: open Home on the previous calendar day. `HomeTab` calls `prepareUpcomingLetter`, which asks `prepare-letter` for tomorrow. The next day, `fetchDailyPush` reads that row.
4. If today has no row yet, one signed-in invoke of `prepare-letter` with `letter_date` set to today is allowed by `allowedDate` (today through two days ahead). The app does not do this when the card opens. If the JSON says `source: "breakout"`, the stored letter is from the catalog. If it says `cached: true`, an existing row was kept.
5. Do not tap the home `REFRESH` control during the recording. It calls `fetchUpcomingLetterForTest`, which deletes tomorrow’s row and runs the model again.

---

## 4. AI feed ranking

`rank-feed` loads up to 48 recent inspirations and skips `is_private` or `is_public == false`. The prompt receives the portrait and up to six interest signals. Nano must return ids from that set. Unknown and duplicate ids are dropped. Fewer than four surviving ids, when that many posts exist, fails the call. The result is cached in `feed_ranks` for that user while the day, portrait stamp, and catalog stamp match. A cached list is not filtered again on the server.

The client asks for that list only when someone is signed in. `placeRankedFirst` keeps only ids that are already in the public list just loaded, then appends the rest in the original `created_at` order. A ranking error, or an empty id list, falls through to the theme filter, then to chronological order. The shelf title stays “For you” in every case. The code does not say the list was written by a model.

| Check | Status |
| --- | --- |
| Only public collections are sent to the model | VERIFIED IN SOURCE ONLY |
| Invalid ids cannot add a post | VERIFIED IN SOURCE ONLY on the server, and VERIFIED BY TEST on the client |
| Ranking is applied in front of the original order | VERIFIED BY TEST |
| Cache key is user, day, portrait stamp, and catalog stamp | VERIFIED IN SOURCE ONLY |
| Model failure leaves a non-AI list | VERIFIED IN SOURCE ONLY |
| Portrait and signals are in the prompt | VERIFIED IN SOURCE ONLY |
| A live ranked response | UNVERIFIED |

The ranking architecture was not rewritten.

---

## 5. Go Deeper

The Go Deeper button calls `_curate(deep: true)`. `curate-card` always runs Nano, then runs Ultra when `deep` is true or Nano sets `needs_ultra`. Ultra is asked for a more concrete `image_brief` and one `caption`. Keywords and the quote stay from Nano. If Ultra throws, the function keeps Nano’s brief, leaves the caption empty, and still paints when it can. The editor shows “Refined by Ultra” only when `used_ultra` is true. On publish, a caption is appended under the quote.

| Check | Status |
| --- | --- |
| Button sends `deep: true` and shows “Refining…” | VERIFIED BY TEST |
| A successful fake result shows the caption, the Ultra label, and an image preview | VERIFIED BY TEST |
| Ultra failure keeps the Nano card | VERIFIED IN SOURCE ONLY |
| Deployed function matches that source | Same download comparison as section 1 |
| A live Ultra call | UNVERIFIED |

---

## 6. Security issues fixed

| Item | What changed |
| --- | --- |
| `lib/judge_demo.dart` | The email and password constants are gone. Both now come from empty `String.fromEnvironment` defines (`JUDGE_EMAIL`, `JUDGE_PASSWORD`). |
| `lib/auth_screen.dart` | The judge button is not built unless both defines are non-empty. Email, password, and guest sign-in are unchanged. |
| `.gitignore` | `.env` and `.env.*` were already ignored, with `!.env.example`. `tool/probe_*.ps1` and `tool/probe_out.txt` are now ignored too. |
| `lib/services/db_service.dart` | Profile-row debug prints were removed from member lookup, profile fetch, and the current-user profile. Other debug prints remain. |
| Git history | This working copy, the original `灵感博物馆` folder, and the backup `灵感博物馆-保底` have no `.git` directory. History could not be searched. |

A pattern scan, which printed file names and rule names only, found Nebius, fal, and Supabase access-token assignments in `.env.local` only. It did not find `sb_secret_`, a JWT, or a quoted password in Dart, TypeScript, or the tool scripts. `tool/probe_nebius.ps1` reads the Nebius key from `.env.local` at runtime. `tool/probe_curate.ps1` does not embed a password. It used to read one out of `lib/judge_demo.dart`, which no longer contains one.

The publishable client key is still in `lib/main.dart`. That is the client key, not a service-role key. It was not removed.

**Rotate before any public copy or any share of this folder:** the judge account password, because it used to live in `lib/judge_demo.dart`; the Nebius key, the fal key, and the Supabase access token in `.env.local`, if this folder or that file has been copied. Nothing was rotated in this phase.

---

## 7. Tests executed

`dart format` on the files touched in this phase. It reformatted four of them.

`flutter analyze lib test`  
Exit code 1 because infos are counted. Two infos, both pre-existing, both in `lib/post_share_sheet.dart:127` (`Share` / `share` deprecated). No errors and no warnings in the files changed here.

`flutter test`  
Exit code 0. **44 tests passed.**

New coverage in `test/ai_workflow_test.dart` and `test/reflection_composer_test.dart`:

- curation JSON parsing, bad image addresses, and missing quote
- daily-letter cache, remote, prepared, catalog, and stock fallback
- rank payload parsing and rejection of unknown post ids
- stock-prompt label versus a prepared letter
- Go Deeper request flag, caption, and Ultra label
- publish with a generated URL, and publish after an image error

Google Fonts failed to download during the test run. Those errors are caught the same way as in the existing layout tests. They did not fail the suite.

No Edge Function test file exists under `supabase/functions`. Deno was not run.

---

## 8. Remaining unverified runtime behavior

- A live Nano response for curation, a letter, or feed ranking.
- A live Ultra response for Go Deeper or “why today”.
- A live FLUX image, the storage upload, and whether the returned URL loads in the browser.
- Whether a published collection shows that generated image.
- Whether the demo account’s card for today is a Nano letter, a catalog letter, or the stock prompt.
- Whether today’s hash falls under the breakout ratio.
- Git history outside this machine. There is no repository here to inspect.

---

## 9. P0 issues still blocking the demo

1. Today’s letter for the recording account was not read. If the card says `STARTING PROMPT`, the pipeline has not stored a letter for today. Use the procedure in section 3. Do not invent a row.
2. Generate Image → storage → preview → published collection has not been run live since the deployed bundle was confirmed. The local tests use fake results. A rehearsal still needs approval for one paid call.
3. The judge password used to be in source. Rotate it before this tree is zipped or published. Do not put the new password back into source.
4. Submission files are still missing: public git repository, license, and a real README. They were intentionally not created in this phase.

No local code defect was found that disconnects Generate, the letter selector, ranking, or Go Deeper. The next-day schedule was not changed.

---

## 10. Recommended next steps

Wait for approval before any of these.

1. Rehearse once on the demo account. Confirm the open card is not `STARTING PROMPT`. If it is, run the signed-in prepare procedure in section 3 and read `source` on the response.
2. Approve one live Generate Image on a short reflection, then publish that collection and confirm the image is visible. If FLUX or the upload fails, the text can still publish and the existing image picker is the on-stage fallback.
3. Rotate the judge password and, if this folder has been shared, the three secrets in `.env.local`.
4. When a public repo is approved, initialize git from a clean tree. Keep `.env.local` and `tool/probe_*.ps1` untracked. Add a license and an English README. Do not commit dart-define passwords.
5. Leave next-day generation, breakout, and the model split (Nemotron for language, FLUX for pixels) as they are.

---

## Files touched

| File | Change |
| --- | --- |
| `lib/judge_demo.dart` | Credentials removed from source |
| `lib/auth_screen.dart` | Judge entrance hidden unless defines are set |
| `lib/services/db_service.dart` | Profile logs removed. Letter read uses `resolveDailyLetter`. Rank ids use `rankIdsFromResponse` |
| `lib/services/curation_service.dart` | `CurationResult.fromResponse` |
| `lib/daily_push.dart` | `isStockFallback`, `resolveDailyLetter` |
| `lib/daily_letter_card.dart` | Stock prompt label |
| `lib/daily_discovery/daily_discovery_screen.dart` | Same label on the full page |
| `lib/community_feed.dart` | `placeRankedFirst` |
| `lib/inspiration_editor_screen.dart` | Test-only publish callback. Production publish path unchanged |
| `test/ai_workflow_test.dart` | New |
| `test/reflection_composer_test.dart` | Go Deeper and publish cases |
| `.gitignore` | Probe scripts and probe output |
