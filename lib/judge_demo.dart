/// Optional judge entrance. Credentials are compile-time defines and are
/// empty in source. Pass them only on a local run:
/// `--dart-define=JUDGE_EMAIL=... --dart-define=JUDGE_PASSWORD=...`
/// Do not commit those values.
class JudgeDemo {
  const JudgeDemo._();

  static const email = String.fromEnvironment('JUDGE_EMAIL');
  static const password = String.fromEnvironment('JUDGE_PASSWORD');

  static bool get isConfigured =>
      email.trim().isNotEmpty && password.isNotEmpty;
}
