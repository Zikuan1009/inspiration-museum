import 'package:flutter/material.dart';
import 'package:inspiration_museum/daily_push.dart';
import 'package:inspiration_museum/daily_push_card.dart';
import 'package:inspiration_museum/services/db_service.dart';

/// 开发测试入口。正式版删除这个文件，以及信封和首页上的调用。
class NextLetterTestButton extends StatelessWidget {
  const NextLetterTestButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).push(NextLetterTestScreen.route());
      },
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Text(
          'REFRESH',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

class NextLetterTestScreen extends StatefulWidget {
  const NextLetterTestScreen({super.key});

  static Route<void> route() {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondary) => const NextLetterTestScreen(),
      transitionsBuilder: (context, animation, secondary, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  @override
  State<NextLetterTestScreen> createState() => _NextLetterTestScreenState();
}

class _NextLetterTestScreenState extends State<NextLetterTestScreen> {
  DailyPush? _push;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final push = await SupabaseDBService.instance.fetchUpcomingLetterForTest();
    if (!mounted) return;
    setState(() {
      _push = push;
      _failed = push == null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final push = _push;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: const Text(
                      'BACK',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'REFRESH',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: Colors.black,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Colors.black),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.4,
                          color: Colors.black,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                      children: [
                        const Text(
                          'Each tap rewrites tomorrow\'s letter. Today\'s letter stays. This entry will be removed from the release.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: Color(0xFF9A9A9A),
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (_failed || push == null)
                          const Text(
                            'The next letter is not ready yet.',
                            style: TextStyle(fontSize: 14, height: 1.5, color: Colors.black),
                          )
                        else
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black, width: 1),
                            ),
                            child: DailyPushCard(push: push),
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
