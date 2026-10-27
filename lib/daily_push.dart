/// `themes` 表里的一个领域。
class MuseumTheme {
  const MuseumTheme({required this.id, required this.name});

  final String id;
  final String name;

  factory MuseumTheme.fromJson(Map<String, dynamic> json) {
    return MuseumTheme(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString().trim() ?? '',
    );
  }
}

/// 存进草稿箱的一封信。同一天再存一次会覆盖那一天。
class LetterDraft {
  const LetterDraft({
    required this.id,
    required this.letterDate,
    required this.push,
  });

  final String id;
  final String letterDate;
  final DailyPush push;
}

/// 每日信件。领域来自旧的随机信；个性化信用关键词、名言、音乐或图片。
class DailyPush {
  const DailyPush({
    required this.keyword,
    required this.quote,
    this.themeName = '',
    this.subThemeName = '',
    this.whyToday = '',
    this.quoteAuthor = '',
    this.musicTitle = '',
    this.musicArtist = '',
    this.imageUrl = '',
    this.cityName = '',
    this.cityCountry = '',
    this.buildingName = '',
    this.buildingCity = '',
    this.filmTitle = '',
    this.filmDirector = '',
    this.bookTitle = '',
    this.bookAuthor = '',
  });

  static const fallback = DailyPush(
    keyword: 'MARGIN',
    quote: 'Today, make an inspiration of your own.',
    themeName: 'DEFAULT',
    subThemeName: '',
  );

  final String keyword;
  final String quote;
  final String themeName;
  final String subThemeName;

  /// Ultra 写的一句「为什么是今天」。旧信和随机信为空。
  final String whyToday;
  final String quoteAuthor;
  final String musicTitle;
  final String musicArtist;
  final String imageUrl;
  final String cityName;
  final String cityCountry;
  final String buildingName;
  final String buildingCity;
  final String filmTitle;
  final String filmDirector;
  final String bookTitle;
  final String bookAuthor;

  List<String> get keywords => [if (keyword.trim().isNotEmpty) keyword.trim()];

  String get pieceTitle {
    for (final value in [
      musicTitle,
      cityName,
      buildingName,
      filmTitle,
      bookTitle,
    ]) {
      final text = value.trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String get pieceDetail {
    if (musicTitle.trim().isNotEmpty) return musicArtist.trim();
    if (cityName.trim().isNotEmpty) return cityCountry.trim();
    if (buildingName.trim().isNotEmpty) return buildingCity.trim();
    if (filmTitle.trim().isNotEmpty) return filmDirector.trim();
    if (bookTitle.trim().isNotEmpty) return bookAuthor.trim();
    return '';
  }

  /// 用这封信开始写一篇时带上的词。关键词在前，当天那一件在后。
  List<String> get creationKeywords {
    final words = <String>[];
    final main = keyword.trim();
    final piece = pieceTitle;
    if (main.isNotEmpty) words.add(main);
    if (piece.isNotEmpty && piece != main) words.add(piece);
    return words;
  }

  Map<String, String> toLetterJson() {
    return {
      'keyword': keyword,
      'quote': quote,
      'theme_name': themeName,
      'sub_theme_name': subThemeName,
      'why_today': whyToday,
      'quote_author': quoteAuthor,
      'music_title': musicTitle,
      'music_artist': musicArtist,
      'image_url': imageUrl,
      'city_name': cityName,
      'city_country': cityCountry,
      'building_name': buildingName,
      'building_city': buildingCity,
      'film_title': filmTitle,
      'film_director': filmDirector,
      'book_title': bookTitle,
      'book_author': bookAuthor,
    };
  }

  /// The hardcoded card used when no stored letter and no catalog row exist.
  /// A catalog letter is not this card, even when it was not written by a model.
  bool get isStockFallback =>
      keyword == fallback.keyword &&
      quote == fallback.quote &&
      themeName == fallback.themeName &&
      whyToday.trim().isEmpty;

  bool get hasPreparedContent =>
      keyword.trim().isNotEmpty ||
      quote.trim().isNotEmpty ||
      musicTitle.trim().isNotEmpty ||
      imageUrl.trim().startsWith('http') ||
      cityName.trim().isNotEmpty ||
      buildingName.trim().isNotEmpty ||
      filmTitle.trim().isNotEmpty ||
      bookTitle.trim().isNotEmpty;

  factory DailyPush.fromJson(Map<String, dynamic> json) {
    final keyword = json['keyword']?.toString().trim() ?? '';
    final quote = json['quote']?.toString().trim() ?? '';
    final theme = json['theme_name']?.toString().trim() ?? '';
    final subTheme = json['sub_theme_name']?.toString().trim() ?? '';
    final whyToday = json['why_today']?.toString().trim() ?? '';
    final quoteAuthor = json['quote_author']?.toString().trim() ?? '';
    final musicTitle = json['music_title']?.toString().trim() ?? '';
    final musicArtist = json['music_artist']?.toString().trim() ?? '';
    final imageUrl = json['image_url']?.toString().trim() ?? '';
    final push = DailyPush(
      keyword: keyword,
      quote: quote,
      themeName: theme,
      subThemeName: subTheme,
      whyToday: whyToday,
      quoteAuthor: quoteAuthor,
      musicTitle: musicTitle,
      musicArtist: musicArtist,
      imageUrl: imageUrl.startsWith('http') ? imageUrl : '',
      cityName: json['city_name']?.toString().trim() ?? '',
      cityCountry: json['city_country']?.toString().trim() ?? '',
      buildingName: json['building_name']?.toString().trim() ?? '',
      buildingCity: json['building_city']?.toString().trim() ?? '',
      filmTitle: json['film_title']?.toString().trim() ?? '',
      filmDirector: json['film_director']?.toString().trim() ?? '',
      bookTitle: json['book_title']?.toString().trim() ?? '',
      bookAuthor: json['book_author']?.toString().trim() ?? '',
    );
    if (!push.hasPreparedContent) return fallback;
    return push;
  }
}

enum DailyLetterSource { cache, remote, prepared, catalog, fallback }

class DailyLetterResolution {
  const DailyLetterResolution(this.push, this.source);

  final DailyPush push;
  final DailyLetterSource source;
}

/// Chooses today's letter from copies that already exist.
/// Opening the card does not call a model. Cache wins, then the account
/// metadata copy, then `daily_letters`, then a catalog row, then the stock
/// prompt. An empty catalog row is the stock prompt, not a model letter.
DailyLetterResolution resolveDailyLetter({
  DailyPush? cached,
  DailyPush? remote,
  DailyPush? prepared,
  Map<String, dynamic>? randomCatalog,
  bool randomUnavailable = false,
}) {
  if (cached != null) {
    return DailyLetterResolution(cached, DailyLetterSource.cache);
  }
  if (remote != null) {
    return DailyLetterResolution(remote, DailyLetterSource.remote);
  }
  if (prepared != null) {
    return DailyLetterResolution(prepared, DailyLetterSource.prepared);
  }
  if (randomUnavailable || randomCatalog == null) {
    return DailyLetterResolution(
      DailyPush.fallback,
      DailyLetterSource.fallback,
    );
  }
  final keyword = randomCatalog['keyword']?.toString().trim() ?? '';
  final quote = randomCatalog['quote']?.toString().trim() ?? '';
  if (keyword.isEmpty && quote.isEmpty) {
    return DailyLetterResolution(
      DailyPush.fallback,
      DailyLetterSource.fallback,
    );
  }
  return DailyLetterResolution(
    DailyPush.fromJson(randomCatalog),
    DailyLetterSource.catalog,
  );
}
