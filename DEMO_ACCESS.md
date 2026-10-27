# Demo access

This guide is for hackathon judges and reviewers. It describes how to run Inspiration Museum from this repository. It does not assume a public website is already online.

No password is included here. Do not add one.

## Supported platforms

The repository contains Flutter runners for:

- Web
- Android
- iOS
- Windows

There is no Linux or macOS runner in this tree. A successful iOS or Android release build was not recorded during repository preparation. The client used for development and UI checks is Flutter web.

## Demo URL

Not published.

When a public URL exists, the organizer should paste it here and in the Devpost submission. Until then, use a local test build.

## Test build

Not published as a downloadable binary or hosted build.

To run the client locally:

1. Install a Flutter SDK that satisfies the Dart constraint in `pubspec.yaml` (`^3.13.3`).
2. From the repository root, run `flutter pub get`.
3. Put your own Supabase project URL and publishable key in `lib/main.dart`. Do not use a service-role key.
4. Run `flutter run -d chrome`, or `flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080`.

The AI features also need the Edge Functions deployed and the secrets in [README.md](README.md) set on that Supabase project. Without `NEBIUS_API_KEY`, letter preparation, curation, and ranking cannot call the model. Without `FAL_KEY`, text curation can still return and image generation will not.

## Authentication

The sign-in screen supports:

- Email and password sign-in and account creation
- Continue as guest, only if anonymous sign-in is enabled on the Supabase project

Create a normal account with the email form if you are testing against a project that allows public sign-up. Guest entry shows "Guest entry is closed." or "Guest mode is not turned on." when anonymous auth is disabled.

## Demo account

There is no demo password in this repository.

An older judge password was removed from source. The judge button is hidden unless someone builds the app with both of these compile-time defines:

```bash
flutter run --dart-define=JUDGE_EMAIL=judge@example.com --dart-define=JUDGE_PASSWORD=replace-me
```

The organizer should create the demo account in Supabase and send the password through the hackathon's private channel, not through git. Rotate any password that was previously stored in source before the repository is public.

For the Daily Inspiration story to match the product, prepare the account before judging:

1. Sign in with the email form.
2. If that day must not be a random catalog letter, set the breakout ratio to 0 in Backstage before the letter is prepared. Saving Backstage refreshes tomorrow's letter, not the card already on screen.
3. Open Home on the previous calendar day so the app can prepare the next day, or have the operator invoke `prepare-letter` once for today. The open card itself does not do that.
4. Confirm the card is not labeled STARTING PROMPT before a recording.
5. Do not tap REFRESH on Home. That control deletes tomorrow's letter and runs the model again.

The account needs to keep working for the whole judging period. That means the Supabase project, the Edge Function secrets, and this demo user must stay enabled. This repository does not host that project.

## What to try

- Open Daily Inspiration and read the quote. If a "why today" line is present, it came from the Ultra pass. The card may still be a catalog letter. The interface does not label those two cases differently.
- Start a reflection, write a few sentences, and use Generate Image. The preview is FLUX. The keywords and quote are Nemotron Nano.
- Go Deeper asks Ultra to revise the visual description and add a caption. If Ultra fails, the Nano card remains.
- Publish only if the demo account is allowed to post. A published collection shows on the profile gallery.
- The community shelf reorders existing public collections. It does not invent them.

## Known limitations

- Today's card is not generated when it is opened.
- A missing letter becomes a catalog row or the built-in starting prompt.
- The default breakout path can skip the language model.
- Image generation can fail while the text still succeeds.
- Ranking can fail and leave the original order. The shelf title does not change.
- Changing the profile does not rewrite the letter already on screen.
- DM Serif Display and Inter load from the network the first time.
- There is no published demo URL in this tree.

## Troubleshooting

| What you see | What to check |
| --- | --- |
| Sign-in fails immediately | `kSupabaseUrl` and the publishable key in `lib/main.dart`, and that the Supabase project is up |
| Guest entry is closed | Anonymous sign-in in the Supabase Auth settings |
| Daily Inspiration says STARTING PROMPT | No row was stored for today. Use the preparation steps above. Do not expect the open card to generate one |
| Generate Image spins and then shows an error | The `curate-card` function, `NEBIUS_API_KEY`, and the signed-in session |
| Text appears and the image does not | `FAL_KEY`, the `post_images` bucket, and storage permissions |
| Home shelf looks purely chronological | Ranking failed or the cache was empty. That is a supported fallback |
| REFRESH was tapped | Tomorrow's prepared letter was deleted and a new model call was started |

Setup commands and secret names are in [README.md](README.md). System design is in [ARCHITECTURE.md](ARCHITECTURE.md).
