import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:inspiration_museum/community_post.dart';

/// 站外打开的只读页。内容写进页面里，没有点赞、评论或转发。
abstract final class SharePage {
  static Uint8List bytes(CommunityPost post) {
    final title = post.title.trim().isNotEmpty
        ? post.title.trim()
        : (post.theme.trim().isEmpty ? 'INSPIRATION' : post.theme.trim());
    final quote = CommunityPost.quotedText(post.quote);
    final keys = post.keywords
        .map((word) => word.trim())
        .where((word) => word.isNotEmpty)
        .join('  ×  ');
    final body = post.text.trim();
    final image = post.imagePath?.trim() ?? '';
    final hasImage =
        image.startsWith('http://') || image.startsWith('https://');
    final page = '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>${_xml(title)} · Inspiration Museum</title>
<style>
html, body { margin: 0; background: #fff; color: #000; }
body { font-family: "Helvetica Neue", Helvetica, Arial, sans-serif; }
.wrap { max-width: 420px; margin: 0 auto; padding: 28px 24px 40px; }
.brand { margin: 0 0 22px; text-align: center; font-size: 12px; font-weight: 800; letter-spacing: 4px; }
.card { border: 1px solid #000; background: #fff; }
.shot { display: block; width: 100%; height: 240px; object-fit: cover; background: #3a3a3a; }
.pad { padding: 16px 16px 18px; }
.keys { margin: 0; font-size: 11px; font-weight: 700; letter-spacing: 0.4px; color: #9a9a9a; }
.quote { margin: 10px 0 0; font-size: 15px; line-height: 1.6; font-style: italic; }
.title { margin: 12px 0 0; font-size: 22px; line-height: 1.35; font-weight: 800; }
.body { margin: 14px 0 0; font-size: 16px; line-height: 1.75; white-space: pre-wrap; }
.note { margin: 22px 0 0; font-size: 11px; font-weight: 700; letter-spacing: 1.4px; }
</style>
</head>
<body>
<main class="wrap">
<p class="brand">INSPIRATION MUSEUM</p>
<article class="card">
${hasImage ? '<img class="shot" alt="" src="${_xml(image)}"/>' : '<div class="shot"></div>'}
<div class="pad">
${keys.isEmpty ? '' : '<p class="keys">${_xml(keys)}</p>'}
${quote.isEmpty ? '' : '<p class="quote">${_xml(quote)}</p>'}
<h1 class="title">${_xml(title)}</h1>
${body.isEmpty ? '' : '<p class="body">${_xml(body)}</p>'}
<p class="note">View only</p>
</div>
</article>
</main>
</body>
</html>
''';
    return Uint8List.fromList(utf8.encode(page));
  }

  static String _xml(String raw) {
    return raw
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
