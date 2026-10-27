import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:inspiration_museum/inspiration_record.dart';
import 'package:inspiration_museum/inspiration_vault.dart';
import 'package:inspiration_museum/local_image.dart';

class ProfileGalleryScreen extends StatefulWidget {
  const ProfileGalleryScreen({super.key, this.embedded = false});

  /// 作为底部导航的 Tab 内嵌时为 true：隐藏返回按钮。
  final bool embedded;

  @override
  State<ProfileGalleryScreen> createState() => _ProfileGalleryScreenState();
}

class _ProfileGalleryScreenState extends State<ProfileGalleryScreen> {
  late Future<List<InspirationRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = InspirationVault.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: widget.embedded
                        ? null
                        : GestureDetector(
                            onTap: () => Navigator.of(context).maybePop(),
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
                  ),
                  const Spacer(),
                  Text(
                    widget.embedded ? 'MY ROOM' : 'ROOM',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
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
              child: FutureBuilder<List<InspirationRecord>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                      child: Text(
                        'ARRANGE',
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 4,
                          color: Colors.black,
                        ),
                      ),
                    );
                  }
                  final records = snap.data ?? const <InspirationRecord>[];
                  if (records.isEmpty) {
                    return const Center(
                      child: Text(
                        'NOTHING SAVED',
                        style: TextStyle(
                          fontSize: 13,
                          letterSpacing: 3,
                          color: Colors.black,
                        ),
                      ),
                    );
                  }
                  return MasonryGridView.count(
                    padding: const EdgeInsets.all(12),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      return _ArchiveCard(record: records[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({required this.record});

  final InspirationRecord record;

  @override
  Widget build(BuildContext context) {
    final path = record.imagePath;
    final hasImage = path != null && path.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 1.0),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasImage) localFileImage(path, fit: BoxFit.fitWidth),
              if (record.userText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: Text(
                    record.userText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                child: Text(
                  record.keywords.join('  ×  '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          if (record.isPrivate)
            const Positioned(
              top: 8,
              right: 8,
              child: Icon(Icons.lock_outline, size: 14, color: Colors.black),
            ),
        ],
      ),
    );
  }
}
