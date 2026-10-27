# Inspiration Museum — Hackathon Readiness Audit

Audit date: 2026-10-27.  
Audited tree: `灵感博物馆-新界面` (the current working copy).  
Method: source inspection only. No application code was changed. No dependencies were installed. No paid API call was made for this audit.

Verification labels:

- **Inspected** — read from the current source.
- **Not re-run** — a previous local log exists, but this audit did not repeat the call.
- **UNVERIFIED** — not evidenced in this tree.

This directory has no `.git` directory, so commit history, a public remote, and whether secret files were ever committed cannot be checked here.

---

## A. Executive Summary

The product has a real Nebius Token Factory integration and uses NVIDIA Nemotron models for user-facing work: daily-letter drafting, reflection curation, and home-feed ordering. Image pixels are not produced by those models. They come from fal.ai FLUX Schnell. The profile is typed by the user; an LLM does not generate the profile itself.

The strongest AI path is preparing a daily letter: portrait and behavior go to Nemotron Nano, an optional “why today” line goes to Nemotron Ultra, and an optional image goes to FLUX, then the row is stored. Opening today’s card does **not** run that pipeline. It reads a letter already stored for today, or falls back to a random catalog letter, or to a hardcoded fallback.

This audit did not re-run inference. A local probe log records empty `image_error` and `error` fields from an earlier curation call. That is not a fresh end-to-end demo proof.

### Five most important findings

1. Nebius Token Factory and NVIDIA Nemotron Nano are wired into the live app, not a side demo. Nebius AI Cloud is not referenced.
2. Today’s Daily Inspiration can be a random or fallback letter. Personalization is aimed at **tomorrow’s** unopened letter.
3. Generate Image and Go Deeper are connected in code (Nano, optional Ultra, FLUX, storage URL, preview, publish). Live success of that chain was not re-tested in this audit.
4. There is no git repository, license, real README, or demo video in this tree. Those submission items are missing.
5. A judge password is hardcoded in `lib/judge_demo.dart`. API secrets live in `.env.local` and in local probe scripts under `tool/`. None of that is safe to publish as-is.

---

## B. AI Model Inventory

| Provider | Model id in code | Purpose | Called from | Used by the app? | Verification |
| --- | --- | --- | --- | --- | --- |
| Nebius Token Factory | `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B` | Turn a reflection into keywords, quote, image brief, and `needs_ultra` | `supabase/functions/curate-card/index.ts` `curateWithNano` → `complete` | Yes. `CurationService.curate` from Generate Image | Inspected. Live call not re-run |
| Nebius Token Factory | `nvidia/Nemotron-3-Ultra-550b-a55b` | Rewrite the image brief and add a caption | `curate-card` `curateWithUltra` | Yes, when Go Deeper is on or Nano sets `needs_ultra` | Inspected. Live call not re-run |
| fal.ai | FLUX Schnell (`https://fal.run/fal-ai/flux/schnell`) | Paint the reflection image | `curate-card` `paint` | Yes, after a brief exists and `FAL_KEY` is set | Inspected. Not an NVIDIA model |
| Nebius Token Factory | Same Nano id | One-sentence observation from likes, saves, and reflections. Not shown in the UI | `prepare-letter` `refreshObservation` | Yes, when the interest stamp changed | Inspected |
| Nebius Token Factory | Same Nano id | Draft keyword, quote, and one rotating companion (image, music, city, building, film, or book) | `prepare-letter` `draftWithNano` | Yes, for the next letter, unless the breakout branch wins | Inspected |
| Nebius Token Factory | Same Ultra id | One “why today” sentence | `prepare-letter` `whyWithUltra` | Yes, after a Nano draft. Failure leaves the sentence empty and still saves the letter | Inspected |
| fal.ai | FLUX Schnell | Daily-letter image when the rotating piece is an image | `prepare-letter` `paint` / `paintLetter` | Yes, only on that branch | Inspected |
| Nebius Token Factory | Same Nano id | Reorder up to 24 public post ids | `rank-feed` `rankWithNano` | Yes. `CommunityFeed._loadPosts` calls `SupabaseDBService.rankHomeFeed` | Inspected |
| Supabase RPC | `get_random_daily_letter` | Pick a catalog letter. No model call | `prepare-letter` `writeBreakoutLetter`; `SupabaseDBService.fetchDailyPush` | Yes, as a fallback and as the breakout path | Inspected |
| None | Hardcoded `DailyPush.fallback` | Keyword `MARGIN` and a fixed quote | `lib/daily_push.dart` | Yes, if no stored or random letter exists | Inspected |

No other inference providers were found. There is no OpenAI client, no local model runtime, and no Nebius AI Cloud / GPU endpoint.

### Shared call shape

All three functions POST to Nebius chat completions:

- `https://api.tokenfactory.nebius.com/v1/chat/completions`
- Nano also tries `https://api.tokenfactory.eu-north1.nebius.com/v1/chat/completions`
- Ultra also tries `https://api.tokenfactory.us-central1.nebius.com/v1/chat/completions`

Request body: `model`, `messages`, `temperature`, `max_tokens`, and optionally `extra_body.chat_template_kwargs.enable_thinking: false`.  
Auth: `Authorization: Bearer` plus `NEBIUS_API_KEY` from the Edge Function environment. The Flutter app never sees that key.  
Timeout: `AbortSignal.timeout(50_000)` on each attempt.  
Retry: up to two rounds across the regional URLs for transient statuses (`0`, `404`, `429`, `5xx`), with an 800 ms pause before the second round. A timeout aborts immediately in `curate-card`.  
Parsing: first `{...}` block, with a lenient repair in `curate-card` `readObject`. Thinking tags are stripped.  
FLUX auth: `Authorization: Key` plus `FAL_KEY`. Timeout 45 s for generation and 20 s for the image download. JPEG bytes are uploaded to the `post_images` bucket.

`supabase/config.toml` sets `verify_jwt = true` for `curate-card`, `prepare-letter`, and `rank-feed`. Each function also calls `auth.getUser()` with the caller’s bearer token.

---

## C. Nebius / NVIDIA Compliance

| Question | Result | Evidence |
| --- | --- | --- |
| Is Nebius Token Factory integrated? | Yes, in code | Three Edge Functions call `api.tokenfactory.nebius.com` chat completions. The Flutter app invokes those functions by name. |
| Is Nebius AI Cloud integrated? | No evidence | No AI Cloud, instance, or GPU endpoint appears in Dart, TypeScript, or config. |
| Which NVIDIA model is used? | `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B` on every AI path. `nvidia/Nemotron-3-Ultra-550b-a55b` on the deeper branches. | Constants at the top of each function file. |
| What product behavior does it power? | Letter drafting, reflection keywords/quotes/scene briefs, and home ordering. Ultra adds a caption or a “why today” line. | See workflows D and B below. |
| Is it in the user-facing workflow? | Yes | Generate Image, Go Deeper, Home load (`prepareUpcomingLetter` and `rankHomeFeed`), and Backstage saves that refresh tomorrow’s letter. |
| Direct or abstracted? | Abstracted | The app calls `CurationService.curate` and `functions.invoke`. Only the Edge Functions hold the Nebius key and model ids. |
| Successful inference? | **Not re-run.** | `tool/probe_out.txt` contains `image_error=` and `error=` with empty values. That is consistent with an earlier curation response that reported no error. This audit did not repeat it and did not open the probe scripts. |
| Meaningful use, not a demo stub? | Yes, in design | The models choose content and order. They are not a single health-check call. |
| Is Nano’s open-source license proven inside this repo? | **UNVERIFIED** | The repo stores the model id, not a model card or license. The id matches NVIDIA’s Nemotron 3 Nano 30B name. Confirm the current Nebius/NVIDIA license page before submission text claims “open source.” |
| Is Ultra an open-source NVIDIA model? | **UNVERIFIED** | The id is NVIDIA-prefixed. This repo does not prove that the 550B weights are open. Do not rely on Ultra alone for the open-model requirement. |

Image generation must not be described as the NVIDIA model. FLUX Schnell is a separate fal.ai model.

---

## D. Workflow Architecture

### Workflow A — User profile

**Implemented as user-written data, not an LLM profile.**

1. Edit Profile and Backstage write `profiles` columns: username, bio, age, gender, location, school, hobbies, personality, occupation, `letter_forms`, `breakout_ratio`.  
   Files: `lib/edit_profile_screen.dart`, `lib/curation_backstage_screen.dart`, `SupabaseDBService.updateProfile`.
2. No model generates those fields.
3. `prepare-letter` `readProfile` loads them into the Nano prompt. The system text says not to invent missing facts and not to rewrite declared hobbies.
4. Likes, saves, and published reflections insert `interest_signals` (`_noteInterest`). Nano may rewrite `observed_note`. That note is explicitly not shown to the user.
5. A profile save deletes tomorrow’s `daily_letters` row and calls `prepareUpcomingLetter`. Today’s already shown letter is left alone (`_refreshUpcomingLetter`).

So the profile affects later generation. It does not regenerate the letter already on screen.

### Workflow B — Daily Inspiration

**Personalized generation exists, but it is not what runs when the card opens.**

1. `HomeTab` loads `fetchDailyPush` and, separately, fires `prepareUpcomingLetter` without awaiting it (`lib/home_tab.dart`).
2. `fetchDailyPush` only reads, in order: local cache, remote row for **today**, `daily_letters` for **today**, then RPC `get_random_daily_letter`, then `DailyPush.fallback`. The file comment says opening the letter does not wait on a model.
3. `prepareUpcomingLetter` invokes `prepare-letter` with **tomorrow’s** date. Errors are swallowed.
4. `prepare-letter` (`supabase/functions/prepare-letter/index.ts`):
   - If the breakout hash for that user and date falls under `breakout_ratio` (default 30), it stores a **random catalog** letter and skips Nano.
   - Otherwise Nano drafts from the portrait, recent posts, signals, observed note, and letters to avoid. A repeated draft is tried once more with a stricter prompt.
   - Ultra writes `why_today`. If Ultra fails, the letter is still saved.
   - If the rotating companion is `image`, FLUX paints it.
   - The row is upserted into `daily_letters` on `(user_id, letter_date)`.
5. Same stamp and same day returns the stored letter (`cached: true`) and does not call the model again.
6. If signals change while painting, the function returns `{ ready: false, stale: true }` and the client tries once more.

**Inspected conclusion:** content can be personalized and persistent, but the card the judge sees today may be yesterday’s prepared letter, a random catalog letter, or the fallback. Changing Backstage during the demo changes tomorrow, not the open card.

### Workflow C — Reflection image generation

**Code path is connected. This audit did not generate or publish an image.**

1. Generate Image calls `_curate(deep: false)`. Go Deeper calls `_curate(deep: true)`.  
   `lib/inspiration_editor_screen.dart`.
2. `CurationService.curate` invokes `curate-card` with `{ title, text, deep }`.
3. Nano must succeed. Ultra runs when `deep` is true or `needs_ultra` is true. Ultra failure keeps Nano’s text (`curate-card` header comment and catch block).
4. FLUX runs only when there is an image brief and `FAL_KEY`. The JPEG is uploaded to `post_images/{userId}/{uuid}.jpg`. The public URL is `image_url`. A paint or upload failure sets `image_error` and still returns the text.
5. The editor stores `image_url` in `_generatedImageUrl` and shows `_NetworkVisual`. An empty URL sets `_visualError` to `image_error` or a fixed English sentence. Keywords and quote still update.
6. Publish calls `createPost` with `imageUrl: _generatedImageUrl` when the user did not pick a local file. The insert writes `inspirations.image_url`. Editing an existing post uses `attachUploadedImage`.

A previous regression (unquoted model JSON) has a lenient parser in `curate-card` `readObject`. Whether the **deployed** function matches this file is **UNVERIFIED** in this audit.

Widget tests cover loading and error UI with a fake curator. They do not call Nebius or fal.

### Workflow D — Go Deeper

**Implemented as a second model pass, not a chat agent.**

- Button sets `deep: true`.
- Ultra is asked for a more concrete `image_brief` and one `caption`.
- Keywords and the original quote stay from Nano.
- On save, the caption is appended under the quote (`_quoteForSave`).
- The context card can say “Refined by Ultra” when `used_ultra` is true.
- If Ultra fails, the user still gets Nano’s card and, if painting works, Nano’s image. The failure is only logged on the server (`ultra failed`).

### Workflow E — Community discovery

**Not a generative feed. AI reorders an existing public list, with a non-AI fallback.**

1. `fetchPublicInspirations` reads `inspirations` ordered by `created_at` descending, skipping private posts.
2. For a signed-in user, `rank-feed` asks Nano for ids. The result is cached in `feed_ranks` for that user and day while the portrait stamp and catalog stamp match. At most one model call per cache miss. Only Nano is used.
3. `CommunityFeed._placeFirst` puts those ids first and appends everyone else in the original order.
4. If ranking throws or returns no ids, `_bySelectedThemes` filters by the user’s chosen themes. If that set is empty, the chronological list is shown.

Do not describe the home feed as model-written. It is a ranked view of published collections.

---

## E. Agentic Capability Assessment

| Capability | Status | Evidence |
| --- | --- | --- |
| Multi-step processing | Implemented | Letter: observe → draft → optional strict redraft → why-today → optional paint → store. Curation: Nano → optional Ultra → paint → upload. |
| Conditional branches | Implemented | Breakout vs personalized letter; companion rotation; `deep` / `needs_ultra`; rank vs theme filter vs chronological list; image failure still returns text. |
| Structured outputs | Implemented | JSON schemas in the prompts, then parsers. Invalid JSON fails the call (letter returns 502; curation returns 502 for Nano). |
| Context persistence | Implemented | `profiles`, `interest_signals`, `observed_note`, `letter_memory`, `daily_letters`, `feed_ranks`. |
| Personalized decisions | Partially implemented | Prompts include the portrait and signals. Breakout and the random RPC bypass the model. Today’s open card may ignore a profile edit. |
| User feedback | Partially implemented | Likes, saves, and reflections become signals and can refresh tomorrow’s letter. There is no explicit accept/reject of a generated card. |
| Retrieval / external knowledge | Not implemented | No web search, no vector store. Companions are model text plus, for images, FLUX. |
| Tool orchestration | Partially implemented | Fixed server steps (chat, then image HTTP, then storage). The model is not choosing tools. |
| Autonomous task execution | Partially implemented | Opening Home starts tomorrow’s letter in the background. The user does not confirm it. It is one prepared job, not an open-ended agent. |
| Adaptive behavior | Partially implemented | Observed note and explore/breakout hashes change the prompt. No online learning. |

Ordinary “call a model, then call an image API” is a pipeline. The letter pipeline is still the strongest fit for the Best Apps and Agents track, because it branches, remembers prior letters, and uses behavior without overwriting the declared portrait.

---

## F. Reliability and Security

### Demo blockers

| Risk | Severity | Where | What happens |
| --- | --- | --- | --- |
| Today’s letter is not generated on open | P0 for the story, not a crash | `fetchDailyPush`, `prepareUpcomingLetter` | A new judge can see `MARGIN` / “Today, make an inspiration of your own.” or a random catalog letter. Profile edits do not change that card. |
| Letter or rank call is slow or fails closed | P1 | 50 s timeouts, swallowed client errors | Home still loads. The personalized letter or order simply does not appear. No user-facing reason. |
| FLUX or upload fails | P1 | `curate-card` `paint` | Text curation can succeed while the preview shows `image_error`. Publish still works without an image. |
| Deployed function may differ from this source | P0 to confirm | Supabase project, not this tree | This audit cannot see the deployed bundle. |
| Breakout ratio defaults to 30 | P1 | `useBreakout` | About 30% of days skip Nano and store a random letter. A demo day can hit that branch. |
| Publishing surfaces raw errors | P2 | `_save` snackbar `Not published: $error` | A storage or RLS failure can show a long exception on stage. |

Empty profiles are allowed. The letter prompt is told not to invent facts. Quality will be generic.

Duplicate daily generation is guarded by the date row and the signal stamp. Opening the card does not generate a second letter.

Auth boundaries inspected: Edge Functions require a user JWT. The service-role key is read only inside the functions. The client uses the publishable key.

### Secrets and public-repo risks

Values are intentionally omitted.

| Location | Risk | Safe next step |
| --- | --- | --- |
| `lib/judge_demo.dart` | Hardcoded judge email and password, used by the sign-in screen | Remove it before any public repo, or load it from an uncommitted local file. Rotate the password if this tree is shared. |
| `lib/main.dart` `kSupabaseUrl`, `kSupabaseAnonKey` | Project URL and publishable client key in source | Acceptable for a public client only if this key is the publishable one. Do not add the service-role key here. |
| `.env.local` | Local secrets file is present on disk | Keep it untracked. `.gitignore` already ignores `.env` and `.env.*`. This folder is not a git repo yet, so that rule is not in force. |
| `tool/probe_curate.ps1`, `tool/probe_nebius.ps1` | Local probe scripts. Not reviewed line by line, because they are likely to contain keys | Do not add `tool/` probe scripts to a public repo. |
| `lib/services/db_service.dart` | `print` of profile rows and errors (`Profile Data`) | Remove or guard those prints before a recorded demo and before publishing source. |
| Edge Function CORS `*` | Browser origin is open, but `verify_jwt` and `getUser()` still apply | No change required for eligibility. Do not disable JWT checks. |
| Git history | **UNVERIFIED** | There is no `.git` here, so leaked history cannot be ruled in or out. |

---

## G. Submission Readiness Matrix

| Requirement | Status | Evidence |
| --- | --- | --- |
| Functional application | PARTIALLY READY | Flutter app, Supabase data, and three AI functions are implemented. Core demo paths were not re-run live in this audit. |
| Nebius integration | PARTIALLY READY | Token Factory is implemented in source. A fresh successful call was not made here. AI Cloud is absent. |
| NVIDIA open-source model | PARTIALLY READY | Nemotron Nano is called for real product work. The open-license document is not in the repo. |
| Public source repository | MISSING | This tree has no `.git` and no remote. |
| Open-source license | MISSING | No `LICENSE` file. |
| README with setup | MISSING | `README.md` is the default “A new Flutter project.” `pubspec.yaml` description matches that. |
| Working demo or test build | UNVERIFIED | A local web server has been used during UI work. No store build, hosted URL, or release artifact is in the tree. |
| YouTube demo, at most 3 minutes | MISSING | No video link or script file. |
| English project description | MISSING | Product UI strings are largely English. There is no submission blurb in the repo. |
| Technical explanation | MISSING | No architecture doc other than this audit. |
| Model and infrastructure feedback | MISSING | Not written. |
| Work done during the submission period | UNVERIFIED | No changelog or dated commit history in this tree. |

---

## H. Prioritized Implementation Backlog

Do not start these until approved. None of them require a new architecture.

### P0 — Eligibility or a demo that matches the story

1. Create the public repo from a clean tree. Add an OSI license and an English README: Flutter run, Supabase project, and the Edge Function secrets (`NEBIUS_API_KEY`, `FAL_KEY`, service role) without pasting values.  
   Complexity: small. Files: new `README.md`, `LICENSE`. Do not commit `.env.local`, `tool/probe_*.ps1`, or `lib/judge_demo.dart` as-is.
2. Confirm the deployed `curate-card`, `prepare-letter`, and `rank-feed` match this source, on the project referenced by `lib/main.dart`.  
   Complexity: small. No app refactor.
3. Before the recording, make sure the judge account already has a **today** row in `daily_letters` produced by the personalized path, and know whether that day hit `useBreakout`. Do not discover the fallback card on stage.  
   Complexity: operational, not a rewrite.
4. Rotate and remove the hardcoded judge password before the repo is public.  
   Complexity: small. File: `lib/judge_demo.dart`.

### P1 — Demo reliability

5. Add a logged-in, explicit “prepare today’s letter” path only if the judge must change the portrait and see a new card immediately. Today that path does not exist; generation is for tomorrow.  
   Complexity: small, but it is a behavior change. Touch `prepareUpcomingLetter` / `fetchDailyPush` only if you accept showing a wait state.
6. Surface a short English failure when `prepare-letter` or `rank-feed` fails, instead of an empty `catch`. Keep the current fallback so Home still opens.  
   Complexity: small. Files: `lib/services/db_service.dart`, `lib/community_feed.dart`, `lib/home_tab.dart`.
7. Record the three-minute video on a warmed account: open the prepared letter, write, Generate Image, show the preview, publish, then show the new collection. Mention Go Deeper in one sentence if the first image already landed.  
   Complexity: production, not code.
8. Write the submission text from Section C so image generation is clearly FLUX, and Nemotron is clearly the language model.  
   Complexity: writing only.

### P2 — Safe to defer

9. Strip `print` of profile payloads.  
10. Restyle sign-in and onboarding. They are not on the AI path.  
11. Replace the deprecated `Share.share` call. It does not affect eligibility.  
12. Measure frame rate. Not an eligibility item.

---

## I. Recommended Three-Minute Demo Flow

Use only what the code can actually do. Rehearse once on the same account.

1. **0:00–0:20** — Open Home. The Daily Inspiration card must already be a prepared letter (keyword, quote, and a companion), not the `MARGIN` fallback. Say that Nemotron drafted it from the portrait and saved it.
2. **0:20–0:45** — Open the letter. Point at the quote and, if present, “why today.” Do not change Backstage live and expect this card to change.
3. **0:45–1:20** — Start a reflection from that letter. Type two or three sentences.
4. **1:20–2:10** — Tap Generate Image. Wait for the preview. This is Nano for the card and FLUX for the picture. If it errors, use the existing “choose an image” control and say the text curation still succeeded. Do not pretend a missing image arrived.
5. **2:10–2:35** — Publish. Return to Profile or Home and show the new collection.
6. **2:35–3:00** — One sentence on Go Deeper (Ultra rewrites the scene) and one sentence on the feed (Nano reorders existing collections; it does not invent them). Stop.

Skip live account creation, cold letter generation, and a profile edit if the clock is under three minutes.

---

## Files that matter

| File | Why |
| --- | --- |
| `supabase/functions/curate-card/index.ts` | Reflection curation, Ultra branch, FLUX, JSON repair |
| `supabase/functions/prepare-letter/index.ts` | Personalized letter, breakout, memory, image |
| `supabase/functions/rank-feed/index.ts` | Feed reorder and day cache |
| `lib/services/curation_service.dart` | App client for `curate-card` |
| `lib/services/db_service.dart` | `fetchDailyPush`, `prepareUpcomingLetter`, `rankHomeFeed`, `createPost`, interest signals |
| `lib/inspiration_editor_screen.dart` | Generate, Go Deeper, preview, publish |
| `lib/home_tab.dart` | Opens the stored letter and kicks off tomorrow’s prepare |
| `lib/community_feed.dart` | Applies rank, then theme filter, then chronological order |
| `lib/daily_push.dart` | Hardcoded fallback |
| `lib/main.dart` | Supabase project URL and publishable key |
| `lib/judge_demo.dart` | Hardcoded judge credentials |
| `.env.local` | Local server secrets. Do not commit |
| `tool/probe_curate.ps1`, `tool/probe_nebius.ps1` | Local probes. Do not commit |
| `README.md` | Still the Flutter stub |
