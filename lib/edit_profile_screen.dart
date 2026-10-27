import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:inspiration_museum/bauhaus_avatar.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:inspiration_museum/user_model.dart';

/// 编辑资料：白底黑线，保存后返回并刷新档案。
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.user});

  final UserModel user;

  static Route<bool> route(UserModel user) {
    return PageRouteBuilder<bool>(
      transitionDuration: CanvasMotion.standard,
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondary) =>
          EditProfileScreen(user: user),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    );
  }

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _bio;
  late final TextEditingController _gender;
  late final TextEditingController _location;
  late final TextEditingController _school;
  late final TextEditingController _age;
  XFile? _picked;
  Uint8List? _preview;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _name = TextEditingController(text: user.username);
    _bio = TextEditingController(text: user.bio);
    _gender = TextEditingController(text: user.gender);
    _location = TextEditingController(text: user.location);
    _school = TextEditingController(text: user.school);
    _age = TextEditingController(text: user.age?.toString() ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _gender.dispose();
    _location.dispose();
    _school.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _picked = file;
        _preview = bytes;
      });
    } on PlatformException catch (error) {
      _toast(
        'Could not open the album: ${error.message ?? 'permission denied'}',
      );
    } catch (_) {
      _toast('Could not choose a photo.');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ageText = _age.text.trim();
    final age = ageText.isEmpty ? null : int.tryParse(ageText);
    final updated = widget.user.copyWith(
      username: _name.text.trim().isEmpty
          ? widget.user.username
          : _name.text.trim(),
      bio: _bio.text,
      gender: _gender.text,
      location: _location.text,
      school: _school.text,
      age: age,
      clearAge: age == null,
    );
    try {
      await SupabaseDBService.instance.updateProfile(
        updated,
        newAvatarFile: _picked,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save.');
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
      contentPadding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
    );

    return Scaffold(
      backgroundColor: CanvasColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _saving
                        ? null
                        : () => Navigator.of(context).maybePop(false),
                    child: Text('Back', style: CanvasType.label),
                  ),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _saving ? null : _save,
                    child: Text(
                      _saving ? 'Saving…' : 'Save',
                      style: CanvasType.label.copyWith(
                        color: CanvasColors.forest,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: CanvasColors.divider),
            Expanded(
              child: Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                    children: [
                      Center(
                        child: GestureDetector(
                          onTap: _saving ? null : _pickAvatar,
                          child: SizedBox(
                            width: 96,
                            height: 96,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: CanvasColors.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: CanvasColors.divider),
                              ),
                              child: ClipOval(
                                child: _preview != null
                                    ? Image.memory(_preview!, fit: BoxFit.cover)
                                    : widget.user.avatarUrl.trim().isNotEmpty
                                    ? Image.network(
                                        widget.user.avatarUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            BauhausAvatar(
                                              seed: widget.user.id,
                                              size: 96,
                                              border: false,
                                            ),
                                      )
                                    : BauhausAvatar(
                                        seed: widget.user.id,
                                        size: 96,
                                        border: false,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Tap to change photo',
                          style: CanvasType.caption,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _LabeledField(
                        label: 'NAME',
                        child: TextField(
                          controller: _name,
                          enabled: !_saving,
                          cursorColor: CanvasColors.forest,
                          decoration: inputTheme.copyWith(hintText: 'Name'),
                        ),
                      ),
                      _LabeledField(
                        label: 'BIO',
                        child: TextField(
                          controller: _bio,
                          enabled: !_saving,
                          maxLines: 3,
                          cursorColor: CanvasColors.forest,
                          decoration: inputTheme.copyWith(
                            hintText: 'One-line introduction',
                          ),
                        ),
                      ),
                      _LabeledField(
                        label: 'AGE',
                        child: TextField(
                          controller: _age,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          cursorColor: CanvasColors.forest,
                          decoration: inputTheme.copyWith(hintText: 'Number'),
                        ),
                      ),
                      _LabeledField(
                        label: 'GENDER',
                        child: TextField(
                          controller: _gender,
                          enabled: !_saving,
                          cursorColor: CanvasColors.forest,
                          decoration: inputTheme.copyWith(hintText: 'Gender'),
                        ),
                      ),
                      _LabeledField(
                        label: 'LOCATION',
                        child: TextField(
                          controller: _location,
                          enabled: !_saving,
                          cursorColor: CanvasColors.forest,
                          decoration: inputTheme.copyWith(hintText: 'Location'),
                        ),
                      ),
                      _LabeledField(
                        label: 'SCHOOL',
                        child: TextField(
                          controller: _school,
                          enabled: !_saving,
                          cursorColor: CanvasColors.forest,
                          decoration: inputTheme.copyWith(hintText: 'School'),
                        ),
                      ),
                    ],
                  ),
                  if (_saving)
                    const ColoredBox(
                      color: CanvasColors.scrim,
                      child: Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: CanvasColors.textOnInk,
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

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
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
