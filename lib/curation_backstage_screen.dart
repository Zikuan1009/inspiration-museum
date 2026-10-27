import 'package:flutter/material.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/onboarding_screen.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:inspiration_museum/user_model.dart';

/// 首页「策展幕后」：画像、来信里想收到的内容、破圈比例，以及领域。
class CurationBackstageScreen extends StatefulWidget {
  const CurationBackstageScreen({super.key, required this.onSaveThemes});

  final Future<void> Function(List<String> themes) onSaveThemes;

  static Route<bool> route({
    required Future<void> Function(List<String> themes) onSaveThemes,
  }) {
    return PageRouteBuilder<bool>(
      transitionDuration: CanvasMotion.standard,
      reverseTransitionDuration: CanvasMotion.quick,
      pageBuilder: (context, animation, secondary) =>
          CurationBackstageScreen(onSaveThemes: onSaveThemes),
      transitionsBuilder: (context, animation, secondary, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: CanvasMotion.enter,
            reverseCurve: CanvasMotion.exit,
          ),
          child: child,
        );
      },
    );
  }

  @override
  State<CurationBackstageScreen> createState() =>
      _CurationBackstageScreenState();
}

class _CurationBackstageScreenState extends State<CurationBackstageScreen> {
  final _hobbies = TextEditingController();
  final _personality = TextEditingController();
  final _occupation = TextEditingController();
  UserModel? _user;
  Set<String> _pieces = _allPieces.toSet();
  int _ratio = 30;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  bool _themesChanged = false;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hobbies.dispose();
    _personality.dispose();
    _occupation.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final signedIn = AuthService.instance.currentUser != null;
    UserModel? user;
    var failed = false;
    if (signedIn) {
      try {
        user = await SupabaseDBService.instance.getCurrentUserProfile();
      } catch (_) {
        failed = true;
      }
    }
    if (!mounted) return;
    setState(() {
      _loadFailed = failed;
      _signedIn = signedIn && user != null;
      _user = user;
      _hobbies.text = user?.hobbies ?? '';
      _personality.text = user?.personality ?? '';
      _occupation.text = user?.occupation ?? '';
      _pieces = _piecesFrom(user?.letterForms);
      _ratio = user?.breakoutRatio ?? 30;
      _loading = false;
    });
  }

  static const _allPieces = [
    'image',
    'music',
    'city',
    'building',
    'film',
    'book',
  ];

  static const _pieceLabels = {
    'image': 'IMAGE',
    'music': 'MUSIC',
    'city': 'CITY',
    'building': 'BUILDING',
    'film': 'FILM',
    'book': 'BOOK',
  };

  static Set<String> _piecesFrom(List<String>? stored) {
    final forms = stored ?? const ['keyword', 'quote'];
    if (forms.contains('none')) return {};
    final picked = forms.where(_allPieces.contains).toSet();
    if (picked.isEmpty) return _allPieces.toSet();
    return picked;
  }

  List<String> _formsToSave() {
    final forms = [
      'keyword',
      'quote',
      for (final piece in _allPieces)
        if (_pieces.contains(piece)) piece,
    ];
    if (!_allPieces.any(_pieces.contains)) forms.add('none');
    return UserModel.letterFormsFromJson(forms);
  }

  Future<void> _save() async {
    final user = _user;
    if (_saving || user == null) return;
    setState(() => _saving = true);
    final forms = _formsToSave();
    try {
      await SupabaseDBService.instance.updateProfile(
        user.copyWith(
          hobbies: _hobbies.text,
          personality: _personality.text,
          occupation: _occupation.text,
          letterForms: forms,
          breakoutRatio: _ratio,
        ),
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _user = user.copyWith(
          hobbies: _hobbies.text,
          personality: _personality.text,
          occupation: _occupation.text,
          letterForms: forms,
          breakoutRatio: _ratio,
        );
      });
      _toast('Saved. Tomorrow\'s letter will be rewritten with this mix.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save.');
    }
  }

  Future<void> _openSeasoning() async {
    final changed = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        transitionDuration: CanvasMotion.standard,
        reverseTransitionDuration: CanvasMotion.quick,
        pageBuilder: (ctx, animation, secondary) => OnboardingScreen(
          allowDismiss: true,
          onFinished: (themes) async {
            await widget.onSaveThemes(themes);
            if (ctx.mounted) Navigator.of(ctx).pop(true);
          },
        ),
        transitionsBuilder: (context, animation, secondary, child) {
          if (MediaQuery.disableAnimationsOf(context)) return child;
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: CanvasMotion.enter,
              reverseCurve: CanvasMotion.exit,
            ),
            child: child,
          );
        },
      ),
    );
    if (changed == true && mounted) {
      setState(() => _themesChanged = true);
      final userId = AuthService.instance.currentUser?.id ?? '';
      if (userId.isNotEmpty) {
        await SupabaseDBService.instance.refreshUpcomingLetter(userId);
      }
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: CanvasColors.forest,
        content: Text(
          text,
          style: CanvasType.bodySmall.copyWith(color: CanvasColors.textOnInk),
        ),
      ),
    );
  }

  void _togglePiece(String piece) {
    setState(() {
      if (_pieces.contains(piece)) {
        _pieces.remove(piece);
      } else {
        _pieces.add(piece);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const line = UnderlineInputBorder(
      borderSide: BorderSide(color: CanvasColors.divider),
    );
    const focused = UnderlineInputBorder(
      borderSide: BorderSide(color: CanvasColors.forest, width: 1.5),
    );
    final inputTheme = InputDecoration(
      isDense: true,
      hintStyle: CanvasType.body.copyWith(color: CanvasColors.textSecondary),
      border: line,
      enabledBorder: line,
      focusedBorder: focused,
      disabledBorder: line,
      contentPadding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
    );
    final canEdit = _signedIn && !_saving;

    return Scaffold(
      backgroundColor: CanvasColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CanvasSpace.page,
                CanvasSpace.md,
                CanvasSpace.sm,
                CanvasSpace.md,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _saving
                        ? null
                        : () => Navigator.of(context).pop(_themesChanged),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Back', style: CanvasType.label),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Backstage',
                      textAlign: TextAlign.center,
                      style: CanvasType.collectionTitle,
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: !canEdit ? null : _save,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Text(
                        _saving ? 'Saving…' : 'Save',
                        style: CanvasType.label.copyWith(
                          color: canEdit
                              ? CanvasColors.forest
                              : CanvasColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: CanvasColors.divider),
            Expanded(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(CanvasSpace.page),
                      child: Column(
                        children: [
                          CanvasSkeleton(height: 14, width: 180),
                          SizedBox(height: CanvasSpace.xl),
                          CanvasSkeleton(height: 44),
                          SizedBox(height: CanvasSpace.md),
                          CanvasSkeleton(height: 44),
                          SizedBox(height: CanvasSpace.md),
                          CanvasSkeleton(height: 44),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        CanvasSpace.page,
                        CanvasSpace.xl,
                        CanvasSpace.page,
                        CanvasSpace.xxxl,
                      ),
                      children: [
                        Text(
                          'What you type here is never rewritten by your behavior. Saves, likes, and notes are recorded separately and used only to rewrite the next letter before it is opened. Today\'s opened letter stays as it is.',
                          style: CanvasType.bodySmall.copyWith(
                            color: CanvasColors.textSecondary,
                          ),
                        ),
                        if (!_signedIn) ...[
                          const SizedBox(height: CanvasSpace.md),
                          Text(
                            'Sign in to save a portrait. You can still choose fields.',
                            style: CanvasType.bodySmall,
                          ),
                        ],
                        if (_loadFailed) ...[
                          const SizedBox(height: CanvasSpace.md),
                          Text(
                            'Your portrait could not be loaded.',
                            style: CanvasType.bodySmall.copyWith(
                              color: CanvasColors.danger,
                            ),
                          ),
                        ],
                        const SizedBox(height: CanvasSpace.xl),
                        Text('PORTRAIT', style: CanvasType.overline),
                        const SizedBox(height: CanvasSpace.sm),
                        _Field(
                          label: 'HOBBY',
                          child: TextField(
                            controller: _hobbies,
                            enabled: canEdit,
                            maxLines: 2,
                            maxLength: 80,
                            buildCounter: (
                              _, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) => null,
                            cursorColor: CanvasColors.forest,
                            style: CanvasType.body,
                            decoration: inputTheme.copyWith(
                              hintText: 'Hobbies',
                            ),
                          ),
                        ),
                        _Field(
                          label: 'PERSONALITY',
                          child: TextField(
                            controller: _personality,
                            enabled: canEdit,
                            maxLength: 40,
                            buildCounter: (
                              _, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) => null,
                            cursorColor: CanvasColors.forest,
                            style: CanvasType.body,
                            decoration: inputTheme.copyWith(
                              hintText: 'Personality',
                            ),
                          ),
                        ),
                        _Field(
                          label: 'OCCUPATION',
                          child: TextField(
                            controller: _occupation,
                            enabled: canEdit,
                            maxLength: 40,
                            buildCounter: (
                              _, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) => null,
                            cursorColor: CanvasColors.forest,
                            style: CanvasType.body,
                            decoration: inputTheme.copyWith(
                              hintText: 'Occupation',
                            ),
                          ),
                        ),
                        Text('DAILY LETTER', style: CanvasType.overline),
                        const SizedBox(height: CanvasSpace.sm),
                        Text(
                          'Keyword and quote are in every letter. Choose the other pieces you want. One chosen piece arrives each day, in this order.',
                          style: CanvasType.bodySmall.copyWith(
                            color: CanvasColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: CanvasSpace.md),
                        Wrap(
                          spacing: CanvasSpace.sm,
                          runSpacing: CanvasSpace.sm,
                          children: [
                            for (final piece in _allPieces)
                              _PieceChoice(
                                label: _pieceLabels[piece] ?? piece,
                                selected: _pieces.contains(piece),
                                enabled: canEdit,
                                onTap: () => _togglePiece(piece),
                              ),
                          ],
                        ),
                        const SizedBox(height: CanvasSpace.xl),
                        Text('BREAKOUT', style: CanvasType.overline),
                        const SizedBox(height: CanvasSpace.sm),
                        Text(
                          'Breakout $_ratio%. Higher means the letter more often comes straight from a field, instead of from the portrait.',
                          style: CanvasType.bodySmall.copyWith(
                            color: CanvasColors.textSecondary,
                          ),
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: CanvasColors.forest,
                            inactiveTrackColor: CanvasColors.divider,
                            thumbColor: CanvasColors.forest,
                            overlayColor: CanvasColors.forest.withValues(
                              alpha: 0.08,
                            ),
                            trackHeight: 2,
                          ),
                          child: Slider(
                            value: _ratio.toDouble(),
                            min: 0,
                            max: 100,
                            divisions: 20,
                            onChanged: !canEdit
                                ? null
                                : (value) =>
                                      setState(() => _ratio = value.round()),
                          ),
                        ),
                        const SizedBox(height: CanvasSpace.md),
                        Pressable(
                          onTap: _saving ? null : _openSeasoning,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: CanvasColors.surface,
                              borderRadius: CanvasRadius.cardAll,
                              border: Border.all(color: CanvasColors.divider),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(CanvasSpace.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Fields', style: CanvasType.titleSmall),
                                  const SizedBox(height: CanvasSpace.xs),
                                  Text(
                                    'Choose fields. This part ignores the portrait and does not call a model.',
                                    style: CanvasType.bodySmall.copyWith(
                                      color: CanvasColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PieceChoice extends StatelessWidget {
  const _PieceChoice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = enabled ? CanvasColors.text : CanvasColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : CanvasMotion.quick,
          curve: CanvasMotion.standardCurve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? CanvasColors.forest : CanvasColors.surface,
            borderRadius: CanvasRadius.buttonAll,
            border: Border.all(
              color: selected ? CanvasColors.forest : CanvasColors.divider,
            ),
          ),
          child: Text(
            label,
            style: CanvasType.overline.copyWith(
              color: selected ? CanvasColors.textOnInk : ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CanvasSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: CanvasType.overline),
          child,
        ],
      ),
    );
  }
}
