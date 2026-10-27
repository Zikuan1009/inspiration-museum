/// 站内转发写在私信正文里。站外转发是一条只读页面链接。
class PostShareLink {
  static final RegExp _id = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String encode(String postId) => '[[post:$postId]]';

  static String? postIdOf(String text) {
    final match = RegExp(
      r'^\[\[post:([0-9a-fA-F-]{36})\]\]$',
    ).firstMatch(text.trim());
    final id = match?.group(1);
    if (id == null || !_id.hasMatch(id)) return null;
    return id;
  }

  static String preview(String text) {
    return postIdOf(text) == null ? text : 'Shared a piece from the museum';
  }

  static String? pageId() {
    final fromQuery = Uri.base.queryParameters['post']?.trim() ?? '';
    if (_id.hasMatch(fromQuery)) return fromQuery;
    final fragment = Uri.base.fragment.trim();
    final match = RegExp(r'^/?p/([0-9a-fA-F-]{36})$').firstMatch(fragment);
    final id = match?.group(1);
    if (id == null || !_id.hasMatch(id)) return null;
    return id;
  }

}
