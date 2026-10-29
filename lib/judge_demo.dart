/// Public judge entrance. The demo password is never compiled into the app.
///
/// [email] is a dedicated demo identity. It may appear in the public web
/// bundle. Judges type only the password supplied outside this repository.
class JudgeDemo {
  const JudgeDemo._();

  static const email = 'judge@inspiration-museum.app';

  static String get publicEmail => email;
}
