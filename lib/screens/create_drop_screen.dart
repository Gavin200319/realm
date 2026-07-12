import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/supabase_service.dart';

class CreateDropScreen extends StatefulWidget {
  final double lat;
  final double lng;

  const CreateDropScreen({super.key, required this.lat, required this.lng});

  @override
  State<CreateDropScreen> createState() => _CreateDropScreenState();
}

class _CreateDropScreenState extends State<CreateDropScreen> {
  final _captionCtrl = TextEditingController();
  int _radius = 50;
  File? _photo;
  bool _saving = false;
  String? _error;

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _photo = File(picked.path));
    }
  }

  Future<void> _save() async {
    if (_captionCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Add a caption before dropping.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String? mediaUrl;
      if (_photo != null) {
        final bytes = await _photo!.readAsBytes();
        mediaUrl = await SupabaseService.instance.uploadDropPhoto(bytes: bytes);
      }
      await SupabaseService.instance.createDrop(
        lat: widget.lat,
        lng: widget.lng,
        caption: _captionCtrl.text.trim(),
        mediaUrl: mediaUrl,
        unlockRadiusM: _radius,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave a Drop here')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _photo == null
                    ? const Center(child: Icon(Icons.add_a_photo_outlined, size: 32))
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_photo!, fit: BoxFit.cover),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _captionCtrl,
              maxLength: 500,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'What do you want to leave here?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text('Unlock radius: ${_radius}m'),
            Slider(
              value: _radius.toDouble(),
              min: 10,
              max: 200,
              divisions: 19,
              label: '${_radius}m',
              onChanged: (v) => setState(() => _radius = v.round()),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Drop it here'),
            ),
          ],
        ),
      ),
    );
  }
}
