import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';

/// 馆员号 + 一键复制。空值不隐藏，改为醒目的 PARSE_ERR。
class AppIdCopyRow extends StatelessWidget {
  const AppIdCopyRow({super.key, required this.appId, this.loading = false});

  final String? appId;
  final bool loading;

  bool get _missing => !loading && (appId == null || appId!.trim().isEmpty);

  bool get _canCopy {
    if (loading || _missing) return false;
    final value = appId!.trim();
    return value != '--------' && value != 'PARSE ERROR';
  }

  String get _text {
    if (loading) return '--------';
    if (_missing) return 'PARSE ERROR';
    return appId!.trim();
  }

  Future<void> _copy(BuildContext context) async {
    if (!_canCopy) return;
    await Clipboard.setData(ClipboardData(text: appId!.trim()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: CanvasColors.forest,
        duration: const Duration(milliseconds: 1400),
        content: Text(
          'Member number copied',
          style: CanvasType.bodySmall.copyWith(color: CanvasColors.textOnInk),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            'ID: $_text',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CanvasType.caption.copyWith(
              color: _missing
                  ? CanvasColors.danger
                  : CanvasColors.textSecondary,
            ),
          ),
        ),
        if (_canCopy) ...[
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _copy(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Copy',
                style: CanvasType.label.copyWith(
                  fontSize: 12,
                  color: CanvasColors.forest,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
