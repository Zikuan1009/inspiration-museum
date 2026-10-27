# Database reproducibility

This note was written from the client, the Edge Functions, and `supabase/migrations/`. The live Supabase project was not queried, dumped, or modified. No user data was exported.

A fresh project cannot be created from this repository alone. A guessed `CREATE TABLE` script was not added. The missing policies, the profile trigger, and the body of `get_random_daily_letter` are not in source. Writing them from inference could disagree with the database the app already uses.

## What the migrations do cover

Applied in filename order, the SQL files alter or create:

| Migration | Effect |
| --- | --- |
| `20261023170000_daily_letters.sql` | Creates `daily_letters` and a select policy for the owner. |
| `20261023180000_letter_profile.sql` | Adds profile columns `hobbies`, `personality`, `occupation`, `letter_forms`, and letter companion columns. Adds a delete policy on `daily_letters`. Assumes `profiles` already exists. |
| `20261023190000_breakout_ratio.sql` | Adds `profiles.breakout_ratio`, default 30. |
| `20261024160000_interest_signals.sql` | Adds `observed_note` and `interest_stamp` on `profiles`, `signals_stamp` on `daily_letters`, and creates `interest_signals` with owner policies. |
| `20261024170000_letter_memory.sql` | Adds `profiles.letter_memory`. |
| `20261024180000_feed_ranks.sql` | Creates `feed_ranks` with a select policy for the owner. |
| `20261025170000_letter_companions.sql` | Adds city, building, film, and book columns on `daily_letters`. |
| `20261025180000_letter_drafts.sql` | Creates `letter_drafts` with owner policies. |
| `20261025190000_letter_piece_choices.sql` | Updates existing `letter_forms` values. It does not create a table. |

Row Level Security in this directory is limited to `daily_letters`, `interest_signals`, `feed_ranks`, and `letter_drafts`.

## What a fresh deployment is still missing

### Base tables the client uses

The Flutter client never creates these. Their policies are not in the migrations.

| Table | Columns the code reads or writes | Notes |
| --- | --- | --- |
| `profiles` | `id`, `username`, `avatar_url`, `bio`, `followers_count`, `following_count`, `app_id`, `age`, `gender`, `location`, `school`, plus the columns added above | The client updates a row. It does not insert one. `app_id` is read and searched, and the client is not allowed to generate it. Some other path, not in this repo, must create the profile and the id. Count columns are displayed. This repo does not show the trigger that maintains them. |
| `inspirations` | `id`, `author_id`, `user_text`, `quote`, `quote_author`, `keywords`, `is_private`, `is_public`, `image_url`, `image_path`, `theme`, `theme_en`, `aspect_ratio`, `content`, `text`, `created_at` | Insert sets `author_id`, `user_text`, `quote`, `keywords`, `is_private`, and sometimes `image_url`. Other columns are only read, so they may be legacy or optional. |
| `messages` | `sender_id`, `receiver_id`, `content`, `is_read`, `created_at` | Direct messages. |
| `follows` | `follower_id`, `following_id` | Duplicate inserts are treated as conflicts. |
| `likes` | `user_id`, `inspiration_id` | |
| `saves` | `user_id`, `inspiration_id` | |
| `reposts` | `user_id`, `inspiration_id` | |
| `comments` | `id`, `user_id`, `inspiration_id`, `content`, `parent_id`, `created_at` | Joined to `profiles(id, username, avatar_url)`. |
| `comment_likes` | `user_id`, `comment_id` | |
| `themes` | `id`, `name` | Read for the shelf filter. No seed file is in the migrations. |
| `user_theme_preferences` | `user_id`, `theme_id` | Upserted by the client. |

`inspirations` is also joined to `profiles` in feed queries. The exact foreign-key names are not declared in this repo.

### RPC

`get_random_daily_letter(target_user_id)` is called by `SupabaseDBService.fetchDailyPush` and by `prepare-letter`. The letter writer reads `keyword`, `quote`, `theme_name`, and `sub_theme_name` from the result. The function body, the catalog table it reads, and its grants are not in this repository.

### Storage

The code uses two buckets:

- `post_images`, for reflection images, letter images, and a share page uploaded as `application/xhtml+xml`
- `avatars`, for profile images

Paths look like `{userId}/{uuid}.jpg` and `{userId}/share/{postId}.xhtml`. The client then requests a public URL. Bucket creation and policies are not in the migrations. A fresh project needs both buckets, authenticated upload for the signed-in user, and a read policy that matches those public URLs.

### Auth behavior that is not SQL in this repo

- Email and password accounts go through Supabase Auth.
- Guest entry needs anonymous sign-in enabled in the project.
- A new auth user must receive a `profiles` row from a trigger or other server path. That path is not here.

## Safe plan

1. Keep using the existing hosted project for the hackathon demo. Do not run a new schema script against it.
2. When a reproducible script is wanted, export **schema only** from a machine that is already allowed to administer the project. Do not export table data. Review the file for keys, emails, and tokens before committing it.
3. Commit that reviewed schema as a new migration, or as `supabase/schema.sql`, only after it has been compared with the queries in `lib/services/db_service.dart`.
4. Until that file exists, `supabase db push` from this tree is only safe on a database that already has the base tables, the profile trigger, the catalog function, the theme rows, and the two storage buckets.

`README.md` points here from the installation section.
