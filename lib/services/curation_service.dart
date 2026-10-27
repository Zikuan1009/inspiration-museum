import 'package:supabase_flutter/supabase_flutter.dart';

/// `curate-card` 的一次结果。图片失败时 [imageUrl] 为空，文字仍然可用。
class CurationResult {
  const CurationResult({
    required this.keywords,
    required this.quote,
    required this.caption,
    required this.usedUltra,
    this.imageUrl,
    this.imageError,
  });

  final List<String> keywords;
  final String quote;
  final String caption;
  final bool usedUltra;
  final String? imageUrl;
  final String? imageError;

  /// Parses a `curate-card` JSON body. A non-http image address is dropped.
  /// Missing keywords or quote fail the call; an image error does not.
  factory CurationResult.fromResponse(Map<String, dynamic> json) {
    final keywords = [
      for (final item in (json['keywords'] as List?) ?? const [])
        if (item.toString().trim().isNotEmpty) item.toString().trim(),
    ];
    final quote = json['quote']?.toString().trim() ?? '';
    final imageUrl = json['image_url']?.toString().trim() ?? '';
    final imageError = json['image_error']?.toString().trim() ?? '';
    if (keywords.isEmpty || quote.isEmpty) {
      throw StateError('Curation did not finish.');
    }
    return CurationResult(
      keywords: keywords,
      quote: quote,
      caption: json['caption']?.toString().trim() ?? '',
      usedUltra: json['used_ultra'] == true,
      imageUrl: imageUrl.startsWith('http') ? imageUrl : null,
      imageError: imageError.isEmpty ? null : imageError,
    );
  }
}

class CurationService {
  CurationService._();

  static final CurationService instance = CurationService._();

  Future<CurationResult> curate({
    required String title,
    required String text,
    required bool deep,
  }) async {
    final response = await Supabase.instance.client.functions.invoke(
      'curate-card',
      body: {'title': title, 'text': text, 'deep': deep},
    );
    final data = response.data;
    if (data is! Map) {
      throw StateError('Curation did not finish.');
    }
    return CurationResult.fromResponse(Map<String, dynamic>.from(data));
  }

  static String messageOf(Object error) {
    if (error is FunctionsFetchException) return 'The network is unavailable.';
    if (error is FunctionException) {
      final details = error.details;
      if (details is Map) {
        final text = details['error']?.toString().trim() ?? '';
        if (text.isNotEmpty && text.length < 80) return text;
      }
      if (error.status == 401) return 'Sign in first.';
    }
    if (error is StateError) {
      final text = error.message.trim();
      if (text.isNotEmpty && text.length < 80) return text;
    }
    return 'Curation did not finish.';
  }
}
