import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import '../services/data_saver_service.dart';
import '../services/supabase_service.dart';
import '../theme/rm_theme.dart';

/// Posting flow for a single status: pick a photo or a short video,
/// preview it, add an optional caption, then upload. Unlike
/// [CreateFlickScreen] this always posts exactly one piece of media —
/// there's no separate feed to browse afterwards, since the whole
/// point of a status is that it just quietly expires in
/// [SupabaseService.statusMaxVideoDurationSeconds]-and-12-hours time.
class CreateStatusScreen extends StatefulWidget {
  const CreateStatusScreen({super.key});

  @override
  State<CreateStatusScreen> createState() => _CreateStatusScreenState();
}

class _CreateStatusScreenState extends State<CreateStatusScreen> {
  final _captionCtrl = TextEditingController();
  File? _mediaFile;
  String? _mediaType; // 'photo' or 'video'
  VideoPlayerController? _previewCtrl;
  bool _saving = false;
  double _progress = 0;
  String? _error;

  @override
  void dispose() {
    _captionCtrl.dispose();
    _previewCtrl?.dispose();
    super.dispose();
  }

  Future<void> _setVideo(File file) async {
    Duration? duration;
    try {
      final info = await VideoCompress.getMediaInfo(file.path);
      final ms = info.duration;
      if (ms != null) duration = Duration(milliseconds: ms.round());
    } catch (_) {}

    if (duration != null &&
        duration.inSeconds > SupabaseService.statusMaxVideoDurationSeconds) {
      setState(() => _error =
          'That video is ${duration!.inSeconds}s — statuses can be at most '
          '${SupabaseService.statusMaxVideoDurationSeconds} seconds. Trim it and try again.');
      return;
    }

    _previewCtrl?.dispose();
    final ctrl = VideoPlayerController.file(file);
    await ctrl.initialize();
    ctrl.setLooping(true);
    ctrl.play();

    if (!mounted) return;
    setState(() {
      _mediaFile = file;
      _mediaType = 'video';
      _previewCtrl = ctrl;
      _error = null;
    });
  }

  void _setPhoto(File file) {
    _previewCtrl?.dispose();
    setState(() {
      _mediaFile = file;
      _mediaType = 'photo';
      _previewCtrl = null;
      _error = null;
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 90);
    if (picked != null) _setPhoto(File(picked.path));
  }

  Future<void> _pickVideo(ImageSource source) async {
    final picked = await ImagePicker().pickVideo(
      source: source,
      maxDuration:
          Duration(seconds: SupabaseService.statusMaxVideoDurationSeconds),
    );
    if (picked != null) await _setVideo(File(picked.path));
  }

  Future<void> _post() async {
    final file = _mediaFile;
    final mediaType = _mediaType;
    if (file == null || mediaType == null) {
      setState(() => _error = 'Add a photo or video first.');
      return;
    }
    setState(() { _saving = true; _error = null; _progress = 0; });

    try {
      final caption =
          _captionCtrl.text.trim().isEmpty ? null : _captionCtrl.text.trim();

      if (mediaType == 'video') {
        final dataSaver = DataSaverService.instance.enabled;
        File videoToUpload = file;
        try {
          final compressed = await VideoCompress.compressVideo(
            file.path,
            quality:
                dataSaver ? VideoQuality.LowQuality : VideoQuality.MediumQuality,
            deleteOrigin: false,
          );
          if (compressed?.file != null) videoToUpload = compressed!.file!;
        } catch (_) {
          // Fall back to the original file untouched.
        }

        final videoBytes = await videoToUpload.readAsBytes();
        await SupabaseService.instance.createStatus(
          mediaBytes: videoBytes,
          mediaType: 'video',
          extension: 'mp4',
          caption: caption,
          onProgress: (p) => mounted ? setState(() => _progress = p) : null,
        );
      } else {
        final photoBytes = await file.readAsBytes();
        await SupabaseService.instance.createStatus(
          mediaBytes: photoBytes,
          mediaType: 'photo',
          extension: 'jpg',
          caption: caption,
          onProgress: (p) => mounted ? setState(() => _progress = p) : null,
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('New Status'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _mediaFile == null ? _buildPickers() : _buildPreview(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_mediaFile != null)
                    TextField(
                      controller: _captionCtrl,
                      maxLength: 200,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Add a caption…',
                        hintStyle: const TextStyle(color: Colors.white54),
                        counterStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white12,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!,
                          style: TextStyle(color: RMColors.danger, fontSize: 13)),
                    ),
                  const SizedBox(height: 12),
                  if (_mediaFile != null)
                    FilledButton(
                      onPressed: _saving ? null : _post,
                      child: _saving
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                  value: _progress > 0 ? _progress : null),
                            )
                          : const Text('Share to your status'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickers() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_motion_outlined,
              color: Colors.white38, size: 56),
          const SizedBox(height: 8),
          Text('Visible for 12 hours, then it disappears',
              style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _pickPhoto(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text('Take a photo'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _pickVideo(ImageSource.camera),
            icon: const Icon(Icons.videocam_rounded, color: Colors.white),
            label: Text(
                'Record a video (up to ${SupabaseService.statusMaxVideoDurationSeconds}s)',
                style: const TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.white38)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final choice = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: RMColors.surface,
                builder: (_) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.image_outlined),
                        title: const Text('Photo from gallery'),
                        onTap: () => Navigator.pop(context, 'photo'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.video_library_outlined),
                        title: const Text('Video from gallery'),
                        onTap: () => Navigator.pop(context, 'video'),
                      ),
                    ],
                  ),
                ),
              );
              if (choice == 'photo') await _pickPhoto(ImageSource.gallery);
              if (choice == 'video') await _pickVideo(ImageSource.gallery);
            },
            icon: const Icon(Icons.photo_library_outlined, color: Colors.white),
            label: const Text('Choose from gallery', style: TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final ctrl = _previewCtrl;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (_mediaType == 'video')
          (ctrl != null && ctrl.value.isInitialized)
              ? AspectRatio(
                  aspectRatio: ctrl.value.aspectRatio,
                  child: VideoPlayer(ctrl),
                )
              : CircularProgressIndicator(color: RMColors.primary)
        else
          InteractiveViewer(
            child: Image.file(_mediaFile!, fit: BoxFit.contain),
          ),
        Positioned(
          top: 12,
          right: 12,
          child: IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: Colors.black54),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () {
              _previewCtrl?.dispose();
              setState(() {
                _mediaFile = null;
                _mediaType = null;
                _previewCtrl = null;
              });
            },
          ),
        ),
      ],
    );
  }
}
