import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/daily_push.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';

// ---------------------------------------------------------------------------
// 包豪斯几何背景：不对称网格 + 交点空心圆环
// ---------------------------------------------------------------------------

class BauhausGridPainter extends CustomPainter {
  const BauhausGridPainter();

  static const _line = Color(0xFF000000);

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = _line.withValues(alpha: 0.25)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final ringPaint = Paint()
      ..color = _line.withValues(alpha: 0.3)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final verticals = <double>[
      size.width * 0.16,
      size.width * 0.71,
    ];
    final horizontals = <double>[
      size.height * 0.19,
      size.height * 0.52,
      size.height * 0.84,
    ];

    for (final x in verticals) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (final y in horizontals) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    canvas.drawCircle(
      Offset(verticals[1], horizontals[0]),
      36,
      ringPaint,
    );
  }

  @override
  bool shouldRepaint(covariant BauhausGridPainter oldDelegate) => false;
}

class _ThemeBoard {
  const _ThemeBoard({required this.themes, required this.selectedIds});

  final List<MuseumTheme> themes;
  final Set<String> selectedIds;
}

// ---------------------------------------------------------------------------
// 引导页：随机长宽的圆角矩形铺满可选区域。点选或再点取消。
// ---------------------------------------------------------------------------

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onFinished,
    this.allowDismiss = false,
  });

  final Future<void> Function(List<String> themes) onFinished;
  final bool allowDismiss;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const double _hPad = 28;

  late Future<_ThemeBoard> _board;
  List<MuseumTheme> _themes = const [];
  _MosaicNode? _mosaic;
  final Set<String> _selected = <String>{};
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _board = _loadBoard();
  }

  Future<_ThemeBoard> _loadBoard() async {
    final userId = AuthService.instance.currentUser?.id ?? '';
    final db = SupabaseDBService.instance;
    final themes = await db.fetchAvailableThemes();
    final selected = await db.fetchUserSelectedThemes(userId);
    return _ThemeBoard(themes: themes, selectedIds: selected.toSet());
  }

  void _reload() {
    setState(() {
      _board = _loadBoard();
    });
  }

  void _adopt(List<MuseumTheme> themes, Set<String> selectedIds) {
    if (_themes.isNotEmpty) return;
    _themes = themes;
    _selected
      ..clear()
      ..addAll(selectedIds);
    if (themes.isEmpty) return;
    _mosaic = _MosaicNode.build(
      themes.length,
      math.Random(DateTime.now().microsecondsSinceEpoch),
    );
  }

  Future<void> _toggle(MuseumTheme theme) async {
    if (_leaving || theme.id.isEmpty) return;
    final userId = AuthService.instance.currentUser?.id ?? '';
    final wasSelected = _selected.contains(theme.id);
    setState(() {
      if (wasSelected) {
        _selected.remove(theme.id);
      } else {
        _selected.add(theme.id);
      }
    });
    try {
      await SupabaseDBService.instance.toggleThemeSubscription(
        userId,
        theme.id,
        !wasSelected,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasSelected) {
          _selected.add(theme.id);
        } else {
          _selected.remove(theme.id);
        }
      });
    }
  }

  Future<void> _confirm() async {
    if (_leaving || _selected.isEmpty) return;
    final names = [
      for (final theme in _themes)
        if (_selected.contains(theme.id)) theme.name,
    ];
    if (names.isEmpty) return;
    setState(() => _leaving = true);
    await widget.onFinished(names);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.allowDismiss && !_leaving,
      child: Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
            child: CustomPaint(
              painter: BauhausGridPainter(),
              size: Size.infinite,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_hPad, 36, _hPad, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.allowDismiss)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _leaving
                            ? null
                            : () => Navigator.of(context).maybePop(),
                        child: const Text(
                          '←  BACK',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: Color(0xFF000000),
                          ),
                        ),
                      ),
                    ),
                  const Text(
                    'CHOOSE FIELDS',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: -0.4,
                      color: Color(0xFF000000),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'SELECT FIELDS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3.2,
                      color: Color(0xFF000000),
                    ),
                  ),
                  const SizedBox(height: 48),
                  Expanded(
                    child: FutureBuilder<_ThemeBoard>(
                      future: _board,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: Text(
                              'LOADING...',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3,
                                color: Colors.black,
                              ),
                            ),
                          );
                        }
                        if (snapshot.hasError || snapshot.data == null) {
                          return Center(
                            child: GestureDetector(
                              onTap: _reload,
                              child: const Text(
                                'Fields could not be opened. Try again',
                                style: TextStyle(
                                  fontSize: 12,
                                  letterSpacing: 1.2,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          );
                        }
                        final board = snapshot.data!;
                        _adopt(board.themes, board.selectedIds);
                        if (board.themes.isEmpty) {
                          return const Center(
                            child: Text(
                              'No fields to choose yet.',
                              style: TextStyle(
                                fontSize: 12,
                                letterSpacing: 1.2,
                                color: Colors.black,
                              ),
                            ),
                          );
                        }
                        final mosaic = _mosaic;
                        if (mosaic == null) {
                          return const SizedBox.shrink();
                        }
                        return LayoutBuilder(
                          builder: (context, box) {
                            final cells = mosaic.place(
                              Size(box.maxWidth, box.maxHeight),
                            );
                            return Stack(
                              children: [
                                for (final cell in cells)
                                  Positioned.fromRect(
                                    rect: cell.rect,
                                    child: _FieldTile(
                                      label: CommunityPost.themeLabel(
                                        board.themes[cell.index].name,
                                      ),
                                      selected: _selected.contains(
                                        board.themes[cell.index].id,
                                      ),
                                      onTap: () =>
                                          _toggle(board.themes[cell.index]),
                                    ),
                                  ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Choose at least one field',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.2,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _LineButton(
                      label: 'CONFIRM',
                      english: 'CONFIRM',
                      enabled: _selected.isNotEmpty && !_leaving,
                      onTap: _confirm,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _Cell {
  const _Cell(this.index, this.rect);

  final int index;
  final Rect rect;
}

/// 每次打开按随机权重把区域切成大小不一的矩形，拼起来铺满。
class _MosaicNode {
  _MosaicNode.leaf(this.index)
      : fraction = 0,
        vertical = false,
        left = null,
        right = null;

  _MosaicNode.split({
    required this.vertical,
    required this.fraction,
    required this.left,
    required this.right,
  }) : index = -1;

  final int index;
  final bool vertical;
  final double fraction;
  final _MosaicNode? left;
  final _MosaicNode? right;

  bool get isLeaf => left == null;

  static _MosaicNode build(int count, math.Random rng) {
    final order = List<int>.generate(count, (i) => i)..shuffle(rng);
    final weights = List<double>.generate(
      count,
      (_) => 0.45 + rng.nextDouble() * 1.9,
    );
    return _split(order, weights, rng);
  }

  static _MosaicNode _split(
    List<int> order,
    List<double> weights,
    math.Random rng,
  ) {
    if (order.length == 1) return _MosaicNode.leaf(order.single);
    final total = order.fold<double>(0, (sum, i) => sum + weights[i]);
    final target = total * (0.33 + rng.nextDouble() * 0.34);
    var acc = 0.0;
    var cut = 1;
    for (var i = 0; i < order.length - 1; i++) {
      acc += weights[order[i]];
      cut = i + 1;
      if (acc >= target) break;
    }
    cut = cut.clamp(1, order.length - 1);
    final leftIds = order.sublist(0, cut);
    final rightIds = order.sublist(cut);
    final leftWeight = leftIds.fold<double>(0, (sum, i) => sum + weights[i]);
    final fraction =
        (leftWeight / total + (rng.nextDouble() - 0.5) * 0.16).clamp(0.24, 0.76);
    return _MosaicNode.split(
      vertical: rng.nextBool(),
      fraction: fraction,
      left: _split(leftIds, weights, rng),
      right: _split(rightIds, weights, rng),
    );
  }

  List<_Cell> place(Size size, {double gap = 12}) {
    final cells = <_Cell>[];
    _place(Rect.fromLTWH(0, 0, size.width, size.height), gap, cells);
    return cells;
  }

  void _place(Rect rect, double gap, List<_Cell> out) {
    if (isLeaf) {
      out.add(_Cell(index, rect));
      return;
    }
    var cutVertical = vertical;
    final aspect = rect.width / rect.height;
    if (aspect > 1.65) {
      cutVertical = true;
    } else if (aspect < 0.6) {
      cutVertical = false;
    }
    if (cutVertical) {
      final span = _span(rect.width, fraction, gap);
      left!._place(
        Rect.fromLTWH(rect.left, rect.top, span, rect.height),
        gap,
        out,
      );
      right!._place(
        Rect.fromLTWH(
          rect.left + span + gap,
          rect.top,
          math.max(0, rect.width - span - gap),
          rect.height,
        ),
        gap,
        out,
      );
    } else {
      final span = _span(rect.height, fraction, gap);
      left!._place(
        Rect.fromLTWH(rect.left, rect.top, rect.width, span),
        gap,
        out,
      );
      right!._place(
        Rect.fromLTWH(
          rect.left,
          rect.top + span + gap,
          rect.width,
          math.max(0, rect.height - span - gap),
        ),
        gap,
        out,
      );
    }
  }

  static double _span(double total, double fraction, double gap) {
    if (total <= gap) return math.max(0, total * fraction);
    final inner = total - gap;
    const minSide = 84.0;
    var primary = inner * fraction;
    if (inner >= minSide * 2) {
      final secondary = inner - primary;
      if (primary < minSide) {
        primary = minSide;
      } else if (secondary < minSide) {
        primary = inner - minSide;
      }
    }
    return primary;
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          border: Border.all(color: Colors.black, width: 1.0),
          borderRadius: BorderRadius.circular(22),
        ),
        child: SizedBox.expand(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final short = constraints.biggest.shortestSide;
              final pad = short < 100 ? 10.0 : 16.0;
              final innerWidth = math.max(0.0, constraints.maxWidth - pad * 2);
              final base = short >= 180
                  ? 22.0
                  : short >= 120
                      ? 18.0
                      : 15.0;
              return Padding(
                padding: EdgeInsets.all(pad),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: innerWidth,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: base,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: selected ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LineButton extends StatelessWidget {
  const _LineButton({
    required this.label,
    required this.english,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String english;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.22,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 1.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF000000),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  english,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.4,
                    color: Color(0xFF000000),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
