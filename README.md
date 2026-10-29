# Inspiration Museum

Every inspiration deserves a place.

A conventional recommendation feed learns a narrow taste and then keeps you inside it. That filter bubble is useful for retrieval and poor for creative work. Inspiration Museum keeps a different kind of memory. It remembers what you wrote about yourself, notices what you later save and make, and prepares a short discovery for another day, including directions you did not already ask for. You answer that discovery in your own words. The app helps turn the writing into a Collection, and a separate image model can paint a picture from a description of the scene.

The language models draft and arrange words. They do not paint pixels, and they do not choose their own tools.

## Links

| | |
| --- | --- |
| Live demo | https://inspiration-museum-demo.pages.dev/ |
| GitHub | https://github.com/Zikuan1009/inspiration-museum |
| Demo video | https://youtu.be/B1LiwwjQY7Q |

Screenshots are not stored in this repository. There is no downloadable iOS or Android binary here, and no Devpost page is linked from this tree. The in-app wordmark is **Inspiration Museum**. A short brand line, “A MUSEUM OF A BRIGHTER YOU”, can appear with the logo and is off in compact headers.

Judge access is described in [DEMO_ACCESS.md](DEMO_ACCESS.md).

## Product overview

You open Home and find a Daily Inspiration card: a keyword, a quotation, and sometimes one companion, such as a picture, a piece of music, a city, a building, a film, or a book. Opening the card reads a letter that was prepared earlier. It does not call a model at that moment.

From the letter you can write a reflection. Generate Image asks NVIDIA Nemotron, through Nebius Token Factory, for keywords, a quotation, and a visual description. fal.ai FLUX Schnell then paints from that description. Go Deeper asks a larger Nemotron model to sharpen the description and add a caption. You can also choose a photo from your device. When you publish, the piece becomes a Collection on your profile and, if you leave it public, on the community shelf.

The shelf can put public Collections in an order chosen for you. If that call fails, you still see the public list. The model does not invent posts.

Serendipity is intentional. Declared hobbies are not the only signal, and the prompt can be told to step away from them. On some days the prepared letter is a catalog piece instead of a new draft. The product would rather show you something you did not ask for than trap you in yesterday's taste. It is still a fixed pipeline: prepare, read, write, optionally illustrate, then publish. It is not an autonomous agent.

## Core features

These behaviors are implemented in this tree:

- Email and password accounts, plus a guest session when Supabase anonymous sign-in is enabled.
- A public **Explore Judge Demo** entrance. The demo email is already selected and cannot be edited. Judges type only the password, which is distributed separately and is not in the source, the documentation, or the web build.
- A Daily Inspiration card and a full-screen reading view.
- A letter prepared for the next day, with a catalog fallback and a built-in starting prompt when nothing is stored for today.
- A reflection composer with Generate Image, Go Deeper, drafts, and publishing.
- A profile you edit yourself. Those fields are later read by the letter prompt. The model does not write your profile.
- Backstage controls for which companions may appear, and for how often a day skips the model.
- A community shelf, follows, likes, saves, comments, search, and direct messages.
- A share sheet for a Collection.

## AI architecture and model responsibilities

Diagrams and call order are in [ARCHITECTURE.md](ARCHITECTURE.md).

**NVIDIA Nemotron 3 Nano**, id `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B`, through Nebius Token Factory:

- drafts the next Daily Inspiration
- writes a private behavioral note that is stored and not shown
- turns a reflection into keywords, a quotation, and an image brief
- ranks ids of public Collections for the home shelf

**NVIDIA Nemotron 3 Ultra**, id `nvidia/Nemotron-3-Ultra-550b-a55b`, through the same API:

- adds one "why today" line to a prepared letter
- on Go Deeper, or when Nano asks for a second pass, rewrites the image brief and adds a caption

If Ultra fails, the Nano result is kept. This repository does not include a model card that proves Ultra's weights are open. Do not use Ultra alone for an open-model requirement.

**FLUX Schnell** at `https://fal.run/fal-ai/flux/schnell` paints the JPEG from the brief. The Edge Function uploads it to Supabase Storage. Nemotron does not generate the image.

**Supabase** provides authentication, Postgres, Storage (`post_images` and `avatars`), and the Edge Functions `curate-card`, `prepare-letter`, and `rank-feed`. The client calls those functions with the signed-in user's JWT. The Nebius key, the fal key, and the service-role key stay on the server.

### How the next letter is chosen

Home reads today's letter from local cache, then account metadata, then the `daily_letters` row for today, then the catalog function `get_random_daily_letter`, then a built-in starting prompt labeled **STARTING PROMPT**. In the background, without waiting, Home asks `prepare-letter` to write **tomorrow's** letter.

The prompt receives the profile fields you typed: username, bio, age, gender, location, school, hobbies, personality, and occupation. It is told not to invent missing facts. Likes, saves, and published reflections become interest signals. A changed signal can refresh the private note. Saving your profile, or recording a new signal, deletes tomorrow's row and prepares it again. The letter already on screen stays as it is.

Unless Backstage changes it, about 30 percent of days store a catalog letter and skip Nano. The card uses the name Daily Inspiration for both a model draft and a catalog letter. It does not tell them apart.

## Technical stack

| Layer | In this repository |
| --- | --- |
| Client | Flutter and Dart. `pubspec.yaml` requires Dart `^3.13.3`. |
| Interface | Material, the theme in `lib/living_canvas/`, and `google_fonts` |
| Local cache | `shared_preferences` |
| Backend | Supabase Auth, Postgres, Storage, and Edge Functions |
| Language | Nebius Token Factory chat completions, Nemotron Nano and Nemotron Ultra |
| Pictures | fal.ai FLUX Schnell, or a photo from the device |
| Targets | `android/`, `ios/`, `web/`, and `windows/`. There is no `linux/` or `macos/` runner. |

Dependencies are listed in `pubspec.yaml`. iOS and Android release builds were not run for this documentation.

## Installation and configuration

### Prerequisites

- A Flutter SDK that satisfies Dart `^3.13.3`
- A Supabase project that already has the base tables described below
- A Nebius Token Factory API key
- A fal.ai key, if images should be generated
- The Supabase CLI, if you deploy functions from this machine

### Run the client

```bash
flutter pub get
flutter run -d chrome
```

Or:

```bash
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

No iOS or Android binary was produced in this preparation.

### Client configuration

`lib/main.dart` holds `kSupabaseUrl` and `kSupabaseAnonKey`. The app passes that value as the publishable client key. Replace both with your own project.

Use a publishable or anon key only. Do not put a service-role key, a personal access token, a Nebius key, or a fal key in the Flutter client.

This working copy already points at one hosted project. A public fork should use its own.

### Environment variables

`.env.example` lists names only. The Flutter app does not read it.

```bash
supabase secrets set NEBIUS_API_KEY=replace-with-nebius-token-factory-key
supabase secrets set FAL_KEY=replace-with-fal-key
```

Supabase injects `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` into functions. `.env.local` is gitignored. Do not commit real values.

The public demo email is a constant in `lib/judge_demo.dart`. Do not pass the demo password as a dart-define, a URL, or a source constant. That would place it in the public JavaScript bundle.

### Database

The SQL in `supabase/migrations/` is incremental. It expects `profiles` and the social tables to exist, and it does not create storage buckets or `get_random_daily_letter`. The full gap is listed in [DATABASE_REPRODUCIBILITY.md](DATABASE_REPRODUCIBILITY.md).

On a database that already has that base:

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

Do not point `db push` at a production project unless you intend to apply those migrations.

### Storage and functions

Create `post_images` and `avatars` if they are missing. Policies are not in the migrations. The client uploads as the signed-in user and then reads a public URL.

```bash
supabase functions deploy curate-card
supabase functions deploy prepare-letter
supabase functions deploy rank-feed
```

`supabase/config.toml` sets `verify_jwt = true` for all three. Each function also calls `auth.getUser()`. The function source for the public demo is in `supabase/functions/`. This release did not redeploy those functions and did not make a live model call.

### Tests

```bash
flutter analyze
flutter test
```

`flutter analyze` counts infos as issues. Two existing infos point at the deprecated `Share.share` call in `lib/post_share_sheet.dart`. Tests that cannot reach the Google Fonts host log a font error and still pass.

## Known limitations

- Opening Daily Inspiration does not generate a letter. Personalization is prepared for a later day.
- A new account can see a catalog letter or the starting prompt.
- The default breakout ratio can skip Nano and store a catalog letter.
- REFRESH on Home deletes tomorrow's letter and runs preparation again. It is a test control. Do not use it in a recording.
- Ultra's open-weight status is not documented here.
- A live Nano, Ultra, or FLUX call was not run for this documentation pass.
- If painting fails, the text can still return and the preview shows an image error.
- Ranking reorders public Collections. It does not write them. On failure the shelf stays in the original order, or a theme filter, and the title stays "For you".
- This repository is not a complete database bootstrap. See [DATABASE_REPRODUCIBILITY.md](DATABASE_REPRODUCIBILITY.md).
- Guest sign-in fails with a visible message if anonymous auth is disabled.
- iOS and Android release builds were not run here.
- DM Serif Display and Inter are fetched from the network on first launch.
- Launcher icons are still the default Flutter logo.

## License

Original source code is under the MIT License, to the extent the copyright holder can grant it. See [LICENSE](LICENSE).

The copyright line in `LICENSE` is `Copyright (c) 2026 Zikuan Zhao`. The holder is a personal name, not a team or organization.

The MIT grant does not cover the Inspiration Museum name, the brand mark drawn in `lib/brand/museum_brand.dart`, third-party fonts and packages, the Flutter logo used as launcher icons, user content, or generated images. No trademark registration is claimed. Read [ASSET_LICENSES.md](ASSET_LICENSES.md).

The bundled Noto Serif SC subset is under the SIL Open Font License 1.1. The notice is in [assets/fonts/OFL-NotoSerifSC.txt](assets/fonts/OFL-NotoSerifSC.txt).
