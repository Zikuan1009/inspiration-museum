import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inspiration_museum/judge_demo.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 包豪斯登录页：登入 / 注册分轨，外加游客探索。
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  /// 已有会话（含匿名）直接放行；否则推出本页，成功后返回 true。
  static Future<bool> require(BuildContext context) async {
    if (AuthService.instance.isSignedIn) return true;
    return present(context);
  }

  /// 无论当前是否已登录，都打开本页（游客升级为邮箱账号时使用）。
  static Future<bool> present(BuildContext context) async {
    final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
      PageRouteBuilder<bool>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (context, animation, secondary) => const AuthScreen(),
        transitionsBuilder: (context, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    return ok == true;
  }

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool isLoginMode = true;
  bool _judgeMode = false;
  String? _emailError;
  String? _passwordError;
  bool _busy = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toggleMode() {
    if (_busy) return;
    setState(() {
      _judgeMode = false;
      isLoginMode = !isLoginMode;
      _emailError = null;
      _passwordError = null;
    });
  }

  void _openJudgeDemo() {
    if (_busy) return;
    setState(() {
      _judgeMode = true;
      isLoginMode = true;
      _email.text = JudgeDemo.publicEmail;
      _password.clear();
      _emailError = null;
      _passwordError = null;
    });
  }

  void _leaveJudgeDemo() {
    if (_busy) return;
    setState(() {
      _judgeMode = false;
      _email.clear();
      _password.clear();
      _emailError = null;
      _passwordError = null;
    });
  }

  bool _validate() {
    final email = _judgeMode ? JudgeDemo.publicEmail : _email.text.trim();
    final password = _password.text;
    String? emailError;
    String? passwordError;

    if (email.isEmpty) {
      emailError = 'Enter an email.';
    } else if (!_emailPattern.hasMatch(email)) {
      emailError = 'That email does not look right.';
    }

    if (password.isEmpty) {
      passwordError = 'Enter a password.';
    } else if (password.length < 6) {
      passwordError = 'Use at least 6 characters.';
    }

    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
    });
    return emailError == null && passwordError == null;
  }

  Future<void> _finish() async {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_validate()) return;

    setState(() {
      _busy = true;
      _emailError = null;
      _passwordError = null;
    });

    final email = _judgeMode ? JudgeDemo.publicEmail : _email.text.trim();
    final password = _password.text;
    final auth = AuthService.instance;

    try {
      if (isLoginMode || _judgeMode) {
        await auth.signInWithEmail(email: email, password: password);
      } else {
        await auth.signUpWithEmail(email: email, password: password);
      }
      if (!mounted) return;
      if (AuthService.instance.currentSession == null) {
        setState(() => _passwordError = 'Confirm your email first.');
        return;
      }
      await _finish();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _passwordError = isLoginMode
            ? _mapLoginError(error)
            : _mapSignUpError(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _passwordError = 'The network is unavailable.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enterAsGuest() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _emailError = null;
      _passwordError = null;
    });
    try {
      await AuthService.instance.signInAnonymously();
      await _finish();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _passwordError = _mapSignUpError(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _passwordError = 'Guest entry is closed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _mapLoginError(AuthException error) {
    final code = (error.code ?? '').toLowerCase();
    final message = error.message.toLowerCase();
    if (code == 'email_not_confirmed' || message.contains('not confirmed')) {
      return 'Confirm your email first.';
    }
    if (code == 'over_request_rate_limit' || message.contains('rate limit')) {
      return 'Too many attempts. Try again shortly.';
    }
    if (AuthService.isUnknownUser(error)) {
      return 'Wrong email or password.';
    }
    if (error.message.trim().isNotEmpty && error.message.length < 80) {
      return error.message;
    }
    return 'Wrong email or password.';
  }

  String _mapSignUpError(AuthException error) {
    final code = (error.code ?? '').toLowerCase();
    final message = error.message.toLowerCase();
    if (AuthService.isAlreadyRegistered(error)) {
      return 'That email is already registered.';
    }
    if (code == 'email_not_confirmed' || message.contains('not confirmed')) {
      return 'Confirm your email first.';
    }
    if (code == 'weak_password' || message.contains('weak password')) {
      return 'That password is too weak.';
    }
    if (code == 'over_request_rate_limit' || message.contains('rate limit')) {
      return 'Too many attempts. Try again shortly.';
    }
    if (code == 'anonymous_provider_disabled') {
      return 'Guest mode is not turned on.';
    }
    if (error.message.trim().isNotEmpty && error.message.length < 80) {
      return error.message;
    }
    return 'Could not confirm your identity.';
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final alreadyGuest = AuthService.instance.isAnonymous;
    final primaryLabel = _busy
        ? 'PROCESSING...'
        : (_judgeMode
              ? 'Enter Museum'
              : (isLoginMode ? 'ENTER' : 'CREATE ACCOUNT'));
    final modeLabel = _judgeMode
        ? 'JUDGE DEMO'
        : (isLoginMode ? 'LOG IN' : 'REGISTER');

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
              children: [
                if (canPop)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _busy
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Padding(
                        padding: EdgeInsets.only(bottom: 48, right: 20, top: 4),
                        child: Text(
                          '←',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                            color: Colors.black,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 36),
                const Text(
                  'IDENTIFY',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    height: 0.95,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  modeLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, thickness: 1, color: Colors.black),
                if (_judgeMode) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Use the demo password provided in the hackathon submission.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w400,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const _LockedIdentity(value: JudgeDemo.email),
                  if (_emailError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _emailError!,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.8,
                        height: 1.4,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ] else ...[
                  const SizedBox(height: 48),
                  _UnderlineField(
                    controller: _email,
                    label: 'EMAIL',
                    hint: 'name@museum.mail',
                    keyboardType: TextInputType.emailAddress,
                    error: _emailError,
                    enabled: !_busy,
                    textInputAction: TextInputAction.next,
                  ),
                ],
                const SizedBox(height: 32),
                _UnderlineField(
                  controller: _password,
                  label: 'PASSWORD',
                  hint: 'At least 6 characters',
                  obscure: true,
                  error: _passwordError,
                  enabled: !_busy,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 48),
                GestureDetector(
                  onTap: _busy ? null : _submit,
                  child: ColoredBox(
                    color: Colors.black,
                    child: SizedBox(
                      height: 52,
                      child: Center(
                        child: Text(
                          primaryLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.4,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (!_judgeMode)
                  GestureDetector(
                    onTap: _busy ? null : _openJudgeDemo,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.fromBorderSide(
                          BorderSide(color: Colors.black, width: 1.5),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Explore Judge Demo',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: Colors.black,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Explore our prepared demo collection.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF5C5C5C),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!_judgeMode) const SizedBox(height: 20),
                GestureDetector(
                  onTap: _busy
                      ? null
                      : (_judgeMode ? _leaveJudgeDemo : _toggleMode),
                  child: Text(
                    _judgeMode
                        ? 'Back to sign in'
                        : (isLoginMode ? 'Register' : 'Log in'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 1.2,
                      color: Colors.black,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.black,
                      decorationThickness: 1,
                    ),
                  ),
                ),
                if (!alreadyGuest && !_judgeMode) ...[
                  const SizedBox(height: 28),
                  GestureDetector(
                    onTap: _busy ? null : _enterAsGuest,
                    child: const Text(
                      'Continue as guest',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 1.4,
                        color: Colors.black,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.black,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LockedIdentity extends StatelessWidget {
  const _LockedIdentity({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'DEMO ACCOUNT',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.black, width: 2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
                height: 1.35,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UnderlineField extends StatelessWidget {
  const _UnderlineField({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscure = false,
    this.enabled = true,
    this.error,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;
  final bool enabled;
  final String? error;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
            color: Colors.black,
          ),
        ),
        TextField(
          controller: controller,
          obscureText: obscure,
          enabled: enabled,
          cursorColor: Colors.black,
          keyboardType: keyboardType,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          inputFormatters: [LengthLimitingTextInputFormatter(128)],
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.6,
            color: Colors.black,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Color(0xFFB4B4B4),
              letterSpacing: 0.4,
            ),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.black, width: 2),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.black, width: 2),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.black, width: 3),
            ),
            disabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.black, width: 2),
            ),
            contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.8,
              height: 1.4,
              color: Colors.black,
            ),
          ),
        ],
      ],
    );
  }
}
