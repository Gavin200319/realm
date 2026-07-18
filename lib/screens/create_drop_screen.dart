import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../models/drop.dart';
import '../services/supabase_service.dart';
import '../services/onboarding_service.dart';
import '../services/drop_events.dart';
import '../theme/rm_theme.dart';
import '../widgets/tutorial_overlay.dart';
import '../widgets/location_autocomplete_field.dart';
import '../widgets/upload_progress_toast.dart';

/// One file the user has picked to attach to this drop, plus everything
/// needed to preview and later upload it.
class _PickedMedia {
  final File file;
  final String mediaType; // 'photo' | 'video' | 'document'
  final String fileName;
  int? sizeBytes;

  _PickedMedia({
    required this.file,
    required this.mediaType,
    required this.fileName,
    this.sizeBytes,
  });

  String get extension {
    final parts = file.path.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : 'bin';
  }
}

class CreateDropScreen extends StatefulWidget {
  final double lat;
  final double lng;

  CreateDropScreen({super.key, required this.lat, required this.lng});

  @override
  State<CreateDropScreen> createState() => _CreateDropScreenState();
}

class _CreateDropScreenState extends State<CreateDropScreen>
    with SingleTickerProviderStateMixin {
  final _captionCtrl = TextEditingController();
  final _userSearchCtrl = TextEditingController();
  int _radius = 50;
  final List<_PickedMedia> _mediaList = [];
  String _visibility = 'public';
  bool _allowDownload = true;
  List<String> _allowedUsers = [];
  List<Map<String, dynamic>> _userSuggestions = [];
  bool _saving = false;
  bool _searchingUsers = false;
  bool _showTutorial = false;
  String? _error;

  late AnimationController _enterCtrl;
  late Animation<double> _enterFade;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 400),
    )..forward();
    _enterFade = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _checkTutorial();
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _userSearchCtrl.dispose();
    _enterCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkTutorial() async {
    final show = await OnboardingService.instance.shouldShowDropTutorial();
    if (mounted) setState(() => _showTutorial = show);
  }

  /// Reads file size off disk (falls back to null on any read error —
  /// we'd rather show "no size" than block the pick).
  Future<int?> _sizeOf(File file) async {
    try {
      return await file.length();
    } catch (_) {
      return null;
    }
  }

  Future<void> _addPicked(File file, String mediaType, String name) async {
    final size = await _sizeOf(file);
    if (!mounted) return;
    setState(() {
      _mediaList.add(_PickedMedia(
        file: file,
        mediaType: mediaType,
        fileName: name,
        sizeBytes: size,
      ));
      _error = null;
    });
  }

  /// Quick single photo capture straight from the camera.
  Future<void> _capturePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked != null) {
      await _addPicked(File(picked.path), 'photo', picked.name);
    }
  }

  /// Pick one or more photos from the gallery.
  Future<void> _pickPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null) return;
    for (final f in result.files) {
      if (f.path == null) continue;
      await _addPicked(File(f.path!), 'photo', f.name);
    }
  }

  /// Pick one or more videos.
  Future<void> _pickVideos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    if (result == null) return;
    for (final f in result.files) {
      if (f.path == null) continue;
      await _addPicked(File(f.path!), 'video', f.name);
    }
  }

  /// Pick one or more documents.
  Future<void> _pickDocuments() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'ppt', 'pptx'],
      allowMultiple: true,
    );
    if (result == null) return;
    for (final f in result.files) {
      if (f.path == null) continue;
      await _addPicked(File(f.path!), 'document', f.name);
    }
  }

  void _removeMedia(int index) {
    setState(() => _mediaList.removeAt(index));
  }

  Future<void> _searchUsers(String query) async {
    if (query.length < 2) {
      setState(() => _userSuggestions = []);
      return;
    }
    setState(() => _searchingUsers = true);
    try {
      final results = await SupabaseService.instance.searchUsers(query);
      setState(() {
        _userSuggestions = results
            .where((u) => !_allowedUsers.contains(u['username']))
            .toList();
      });
    } finally {
      if (mounted) setState(() => _searchingUsers = false);
    }
  }

  void _addUser(String username) {
    setState(() {
      if (!_allowedUsers.contains(username)) _allowedUsers.add(username);
      _userSearchCtrl.clear();
      _userSuggestions = [];
    });
  }

  Future<void> _save() async {
    if (_captionCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Add a caption before dropping.');
      return;
    }
    if (_visibility == 'private' && _allowedUsers.isEmpty) {
      setState(() => _error =
          'Add at least one person to the allowlist, or set visibility to public.');
      return;
    }
    setState(() { _saving = true; _error = null; });

    UploadProgressToast? toast;
    try {
      final mediaItems = <Map<String, dynamic>>[];

      if (_mediaList.isNotEmpty) {
        toast = UploadProgressToast(context);
        toast.show(
          fileName: _mediaList.first.fileName,
          fileCount: _mediaList.length,
        );

        for (var i = 0; i < _mediaList.length; i++) {
          final item = _mediaList[i];
          final bytes = await item.file.readAsBytes();
          final url = await SupabaseService.instance.uploadDropMedia(
            bytes: bytes,
            mediaType: item.mediaType,
            extension: item.extension,
            onProgress: (p) => toast?.update(
              fileName: item.fileName,
              fileIndex: i + 1,
              fileCount: _mediaList.length,
              progress: p,
            ),
          );
          mediaItems.add({
            'url': url,
            'type': item.mediaType,
            'size_bytes': item.sizeBytes ?? bytes.length,
            'name': item.fileName,
          });
        }

        await toast.finish();
      }

      final primary = mediaItems.isNotEmpty ? mediaItems.first : null;

      await SupabaseService.instance.createDrop(
        lat: widget.lat,
        lng: widget.lng,
        caption: _captionCtrl.text.trim(),
        mediaUrl: primary?['url'] as String?,
        mediaType: primary?['type'] as String?,
        mediaSizeBytes: primary?['size_bytes'] as int?,
        allowDownload: _allowDownload,
        mediaItems: mediaItems,
        unlockRadiusM: _radius,
        visibility: _visibility,
      );

      // Grant access to allowlist users
      if (_visibility == 'private' && _allowedUsers.isNotEmpty) {
        final dropId = await SupabaseService.instance
            .fetchLatestDropId(SupabaseService.instance.currentUser!.id);
        if (dropId != null) {
          for (final username in _allowedUsers) {
            await SupabaseService.instance.grantDropAccess(
              dropId: dropId,
              username: username,
            );
          }
        }
      }

      DropEvents.instance.notifyDropCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      await toast?.fail(e.toString());
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: RMColors.background,
          appBar: AppBar(
            title: Text('Leave a Drop'),
            backgroundColor: RMColors.background,
          ),
          body: FadeTransition(
            opacity: _enterFade,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Media picker row
                  Row(
                    children: [
                      _MediaPicker(
                        icon: Icons.photo_camera_rounded,
                        label: 'Photo',
                        selected: _mediaList.any((m) => m.mediaType == 'photo'),
                        onTap: _pickPhotos,
                        onCameraTap: _capturePhoto,
                      ),
                      SizedBox(width: 10),
                      _MediaPicker(
                        icon: Icons.videocam_rounded,
                        label: 'Video',
                        selected: _mediaList.any((m) => m.mediaType == 'video'),
                        onTap: _pickVideos,
                      ),
                      SizedBox(width: 10),
                      _MediaPicker(
                        icon: Icons.insert_drive_file_rounded,
                        label: 'Document',
                        selected:
                            _mediaList.any((m) => m.mediaType == 'document'),
                        onTap: _pickDocuments,
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Tap to pick multiple. Long-press Photo to use the camera.',
                    style: TextStyle(color: RMColors.textHint, fontSize: 11),
                  ),
                  SizedBox(height: 14),

                  // Media preview list
                  AnimatedSwitcher(
                    duration: Duration(milliseconds: 250),
                    child: _mediaList.isEmpty
                        ? SizedBox.shrink()
                        : _buildMediaPreviewList(),
                  ),
                  if (_mediaList.isNotEmpty) SizedBox(height: 14),

                  // Caption
                  TextField(
                    controller: _captionCtrl,
                    maxLength: 500,
                    maxLines: 4,
                    style: TextStyle(color: RMColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'What do you want to leave here?',
                      counterStyle: TextStyle(color: RMColors.textHint),
                    ),
                  ),
                  SizedBox(height: 16),

                  // Unlock radius
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Unlock radius',
                          style: TextStyle(
                              color: RMColors.textSecondary, fontSize: 13)),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: RMColors.primaryDim,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_radius}m',
                          style: TextStyle(
                              color: RMColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: RMColors.primary,
                      inactiveTrackColor: RMColors.border,
                      thumbColor: RMColors.primary,
                      overlayColor: RMColors.primary.withOpacity(0.1),
                    ),
                    child: Slider(
                      value: _radius.toDouble(),
                      min: 10,
                      max: 200,
                      divisions: 19,
                      onChanged: (v) => setState(() => _radius = v.round()),
                    ),
                  ),
                  SizedBox(height: 16),

                  // Visibility
                  Text('Who can see this?',
                      style: TextStyle(
                          color: RMColors.textSecondary, fontSize: 13)),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      _VisibilityChip(
                        label: 'Public',
                        icon: Icons.public_rounded,
                        selected: _visibility == 'public',
                        onTap: () =>
                            setState(() => _visibility = 'public'),
                      ),
                      SizedBox(width: 10),
                      _VisibilityChip(
                        label: 'Private',
                        icon: Icons.lock_rounded,
                        selected: _visibility == 'private',
                        onTap: () =>
                            setState(() => _visibility = 'private'),
                      ),
                    ],
                  ),

                  // Allow download
                  if (_mediaList.isNotEmpty) ...[
                    SizedBox(height: 20),
                    _DownloadToggle(
                      value: _allowDownload,
                      onChanged: (v) => setState(() => _allowDownload = v),
                    ),
                  ],

                  // Allowlist
                  if (_visibility == 'private') ...[
                    SizedBox(height: 20),
                    Text('Who can unlock this?',
                        style: TextStyle(
                            color: RMColors.textSecondary, fontSize: 13)),
                    SizedBox(height: 10),
                    if (_allowedUsers.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _allowedUsers
                            .map((u) => Chip(
                                  label: Text('@$u'),
                                  onDeleted: () => setState(
                                      () => _allowedUsers.remove(u)),
                                  deleteIconColor: RMColors.textSecondary,
                                ))
                            .toList(),
                      ),
                    SizedBox(height: 10),
                    TextField(
                      controller: _userSearchCtrl,
                      style: TextStyle(color: RMColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Search by username',
                        suffixIcon: _searchingUsers
                            ? Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: RMColors.primary),
                                ),
                              )
                            : null,
                      ),
                      onChanged: _searchUsers,
                    ),
                    if (_userSuggestions.isNotEmpty)
                      Container(
                        margin: EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: RMColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: RMColors.border),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                          itemCount: _userSuggestions.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 1, color: RMColors.border),
                          itemBuilder: (context, i) {
                            final u = _userSuggestions[i];
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: RMColors.primaryDim,
                                child: Icon(Icons.person_rounded,
                                    size: 16, color: RMColors.primary),
                              ),
                              title: Text('@${u['username']}',
                                  style: TextStyle(
                                      color: RMColors.textPrimary,
                                      fontSize: 14)),
                              subtitle: Text(u['display_name'] ?? '',
                                  style: TextStyle(
                                      color: RMColors.textSecondary,
                                      fontSize: 12)),
                              onTap: () =>
                                  _addUser(u['username'] as String),
                            );
                          },
                        ),
                      ),
                  ],

                  SizedBox(height: 24),
                  if (_error != null)
                    Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(_error!,
                          style: TextStyle(
                              color: RMColors.danger, fontSize: 13)),
                    ),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text('Drop it here'),
                  ),
                ],
              ),
            ),
          ),
        ),

        if (_showTutorial)
          TutorialOverlay(
            steps: [
              TutorialStep(
                icon: Icons.add_location_alt_rounded,
                title: 'Create a Drop',
                body: 'You\'re pinning content to your exact GPS location. Anyone who walks here can discover it.',
              ),
              TutorialStep(
                icon: Icons.perm_media_rounded,
                title: 'Add any media',
                body: 'Attach a photo, video, or document. The content stays hidden until someone physically unlocks it.',
              ),
              TutorialStep(
                icon: Icons.lock_rounded,
                title: 'Set visibility',
                body: 'Public drops are discoverable by everyone. Private drops are only visible to people you add by username.',
              ),
            ],
            onDone: () async {
              await OnboardingService.instance.markDropTutorialSeen();
              if (mounted) setState(() => _showTutorial = false);
            },
          ),
      ],
    );
  }

  Widget _buildMediaPreviewList() {
    return Column(
      key: ValueKey('media-list'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _mediaList.length; i++) ...[
          if (i > 0) SizedBox(height: 8),
          _MediaPreviewTile(
            media: _mediaList[i],
            onRemove: () => _removeMedia(i),
          ),
        ],
      ],
    );
  }
}

class _MediaPreviewTile extends StatelessWidget {
  final _PickedMedia media;
  final VoidCallback onRemove;

  _MediaPreviewTile({required this.media, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final sizeLabel = formatFileSize(media.sizeBytes);
    if (media.mediaType == 'photo') {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: RMColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Image.file(media.file, height: 140, width: double.infinity, fit: BoxFit.cover),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: _PreviewCaptionBar(
                fileName: media.fileName,
                sizeLabel: sizeLabel,
                onRemove: onRemove,
                dark: true,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: RMColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RMColors.border),
      ),
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            media.mediaType == 'video'
                ? Icons.videocam_rounded
                : Icons.insert_drive_file_rounded,
            color: RMColors.primary,
            size: 24,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  media.fileName,
                  style: TextStyle(
                      color: RMColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (sizeLabel != null)
                  Text(sizeLabel,
                      style: TextStyle(
                          color: RMColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded,
                color: RMColors.textSecondary, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _PreviewCaptionBar extends StatelessWidget {
  final String fileName;
  final String? sizeLabel;
  final VoidCallback onRemove;
  final bool dark;

  _PreviewCaptionBar({
    required this.fileName,
    required this.sizeLabel,
    required this.onRemove,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fileName,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (sizeLabel != null)
                  Text(sizeLabel!,
                      style: TextStyle(
                          color: Colors.white70, fontSize: 10)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, color: Colors.white, size: 16),
          ),
        ],
      ),
    );
  }
}

class _DownloadToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  _DownloadToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: RMColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RMColors.border),
      ),
      child: Row(
        children: [
          Icon(
            value ? Icons.download_rounded : Icons.download_for_offline_outlined,
            size: 18,
            color: value ? RMColors.primary : RMColors.textSecondary,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Allow downloads',
                    style: TextStyle(
                        color: RMColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text('Let people save the attached files to their device',
                    style: TextStyle(
                        color: RMColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: RMColors.primary,
          ),
        ],
      ),
    );
  }
}

class _MediaPicker extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onCameraTap;

  _MediaPicker({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onCameraTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onCameraTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? RMColors.primaryDim : RMColors.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? RMColors.primary : RMColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected ? RMColors.primary : RMColors.textHint,
                  size: 22),
              SizedBox(height: 5),
              Text(label,
                  style: TextStyle(
                      color: selected
                          ? RMColors.primary
                          : RMColors.textHint,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisibilityChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  _VisibilityChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? RMColors.primaryDim : RMColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? RMColors.primary : RMColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color:
                    selected ? RMColors.primary : RMColors.textSecondary),
            SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: selected
                        ? RMColors.primary
                        : RMColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
