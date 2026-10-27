# Third-party assets and licensing notes

This file records what was identified in the Inspiration Museum working tree on 2026-10-27. It is not a legal opinion.

The MIT License in `LICENSE` is intended for original source code the project owner has the right to license. It does not, by itself, do any of the following:

- transfer ownership of the name **Inspiration Museum**
- license the brand mark as a trademark
- license fonts, packages, or other third-party works beyond their own terms
- license user-generated content, private messages, or images stored in Supabase
- claim that every file in the tree was written by the project owner

No trademark registration was found in this repository. Nothing here claims registered trademark protection.

The copyright line in `LICENSE` is `Copyright (c) 2026 Zikuan Zhao`. It is a personal name, not an organization, a project title, or an account username. A Supabase project display name in local CLI metadata was not used.

## Project code and brand

| Item | Where | Finding |
| --- | --- | --- |
| Application source | `lib/`, `test/`, `supabase/functions/`, `supabase/migrations/` | Original project code, once the owner confirms the right to license it under MIT. |
| Brand mark | `lib/brand/museum_brand.dart` | Drawn in code with a `CustomPainter`. No separate logo image file is in the tree. The painter source can be part of the MIT grant. The name and the mark are still the project's branding, not a trademark license. |
| Theme catalog | `assets/data.json` | Bundled in `pubspec.yaml` and loaded by `Catalog.loadFromBundle`. Theme entries are unattributed prompts. The quote list keeps four public-domain Chinese calligraphy sentences. The other quotes are original English prompts labeled `Original prompt`, because the parser requires a non-empty author. See the catalog note below. |

## Fonts

| Item | Where | License status |
| --- | --- | --- |
| Noto Serif SC SemiBold subset | `assets/fonts/NotoSerifSC-Museum.ttf` | The font's own name table says family `Noto Serif SC SemiBold`, version `2.003-H1;hotconv 1.1.1;makeotfexe 2.6.0`, unique id `2.003-H1;GOOG;NotoSerifSC-SemiBold`, copyright `(c) 2017-2024 Adobe (http://www.adobe.com/).`, and license URL `https://openfontlicense.org`. The file is about 5 KB, so it is a subset, not the full family. Flutter registers it as `MuseumSerifSC`; that alias does not change the name inside the font. The SIL Open Font License 1.1 text is in `assets/fonts/OFL-NotoSerifSC.txt`. The name table does not name a Reserved Font Name. |
| DM Serif Display and Inter | Not vendored. Loaded at runtime by `google_fonts` | These families are used by `CanvasType`. They are typically available under the SIL Open Font License. The first run needs a network fetch. Package license for `google_fonts` is separate. |
| Device fallbacks | Named in `typography.dart` | PingFang SC, Hiragino Sans GB, Microsoft YaHei, Noto Sans SC, Songti SC, and similar names are system fonts. They are not bundled. Their licenses stay with the operating system. |

## Images, icons, and generated media

| Item | Finding |
| --- | --- |
| Bitmap logo | No in-app bitmap logo was found. The in-app mark is the painter above. |
| Launcher and web icons | `android/app/src/main/res/mipmap-*/ic_launcher.png`, `ios/Runner/Assets.xcassets/AppIcon.appiconset/`, `web/favicon.png`, `web/icons/`, `windows/runner/resources/app_icon.ico` | The inspected PNG icons are the default Flutter logo, not the Inspiration Museum mark. Flutter and the Flutter logo are Google brands. They are template assets, not covered by this project's MIT License. |
| iOS launch images | `ios/Runner/Assets.xcassets/LaunchImage.imageset/` | The inspected images are blank template placeholders, not product artwork. |
| AI-generated images | Produced at runtime by fal.ai FLUX Schnell and stored in the `post_images` bucket. They are not checked into this repository. Do not describe them as MIT-licensed project assets. |
| User uploads and avatars | Stored in Supabase (`post_images`, `avatars`). They belong to the uploading user, subject to the product's own terms, which are not defined in this repository. |
| Sample posts inside Dart | `lib/community_post.dart` and `lib/mock_cloud.dart` contain unused sample records. Their attributed quotations were replaced with original English prompts labeled `Original prompt`. The surrounding sample prose was left as project-authored text. |

## Dependencies

Direct packages are declared in `pubspec.yaml`: Flutter, `shared_preferences`, `image_picker`, `flutter_staggered_grid_view`, `path_provider`, `supabase_flutter`, `share_plus`, `google_fonts`, and `flutter_lints`.

Each package keeps its own license. Those licenses were not copied into this file and were not re-audited one by one in this preparation. `flutter pub get` followed by the Dart license collector is the way to list them. Edge Functions import `@supabase/supabase-js` from npm at deploy time.

Flutter SDK and the platform runners under `android/`, `ios/`, `web/`, and `windows/` include template files from Flutter. Those template portions remain under Flutter's license even if the rest of the application is MIT.

## Catalog quotations

`assets/data.json` has 104 quote entries. One hundred were attributed modern or translated passages. Their redistribution rights were not verified, so the text and the personal attribution were replaced. The author field cannot be empty: `Catalog._parseQuotes` drops a quote with a blank author. The replacement label is `Original prompt`.

Four entries stay because the bundled wording is the original Chinese, not a translation, and the works are public domain:

| Id | Text in the catalog | Evidence |
| --- | --- | --- |
| `q_calli_01` | 一点成一字之规，一字乃终篇之准。 | Sun Guoting, *Shupu* (Tang dynasty; he died in 688). The sentence appears in the Wikisource transcription of 书谱. |
| `q_calli_02` | 察之者尚精，拟之者贵似。 | Same work and transcription. |
| `q_calli_03` | 书，如也，如其学，如其才，如其志，总之曰如其人而已。 | Liu Xizai, *Yigai* (published 1873; he died in 1881). Wikisource marks 艺概 as public domain because the author died more than 100 years ago and the work was published before 1931. Printed editions differ slightly in punctuation. The words match the sentence quoted from 书概. |
| `q_calli_04` | 书者，散也。欲书先散怀抱。 | Cai Yong, *Bilun* (Eastern Han; he died in 192). Wikisource transcribes the opening as 书者，散也。欲书，先散怀抱 and marks the work public domain. The catalog omits one comma and stops before 任情恣性. |

Theme entries have no author field. They were not treated as attributed quotations and were not rewritten.

## Unresolved before publication

1. The launcher icons are the Flutter logo. Shipping the unmodified Flutter template is normal for a Flutter project, and it is not a license to treat that logo as Inspiration Museum art. Replace the icons before a public store listing if the product should not display the Flutter logo.
2. `web/view.html` is unused by the app. It is gitignored and was not deleted. Remove the ignore only if that page should be published.
3. Do not apply the MIT License to Supabase content, messages, generated images, the Noto font, or the Flutter logo.
