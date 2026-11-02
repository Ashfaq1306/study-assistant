import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/feedback.dart';

/// Most photos a session can hold (the server enforces the same limit).
const maxStudyPhotos = 4;

/// A study photo's bytes, fetched once with the signed-in account.
final studyPhotoProvider = FutureProvider.family<Uint8List, String>((ref, id) => ref.watch(studyApiProvider).photo(id));

/// The image type from its first bytes (the camera gives JPEG; the gallery may give PNG or WebP).
String imageMime(Uint8List bytes) {
  if (bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50) return 'image/png';
  if (bytes.length > 12 && String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') return 'image/webp';
  return 'image/jpeg';
}

/// Asks camera or gallery, then returns a phone-sized, compressed photo (or null).
Future<Uint8List?> pickStudyPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.photo_camera_rounded, color: AppColors.violet),
            title: const Text('Take a photo'),
            subtitle: const Text('Your book page, notes or worksheet'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: Icon(Icons.photo_library_rounded, color: AppColors.violet),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null) return null;
  try {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 72);
    return await file?.readAsBytes();
  } on Exception {
    if (context.mounted) showSnack(context, "Couldn't open the camera. Check the camera permission in Settings.");
    return null;
  }
}

/// A rounded thumbnail; tap to see the photo full screen.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({super.key, required this.image, this.size = 84, this.onRemove});

  final ImageProvider image;
  final double size;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Semantics(
          button: true,
          label: 'Study photo. Tap to open.',
          child: GestureDetector(
            onTap: () => showPhotoViewer(context, image),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image(image: image, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
            ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: -8,
            right: -8,
            child: Material(
              color: AppColors.coral,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(5),
                  child: Icon(Icons.close_rounded, size: 16, color: Colors.white, semanticLabel: 'Remove photo'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A photo stored on the server, loaded with the signed-in account.
class ServerPhotoThumb extends ConsumerWidget {
  const ServerPhotoThumb({super.key, required this.photoId, this.size = 84, this.onRemove});

  final String photoId;
  final double size;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = ref.watch(studyPhotoProvider(photoId));
    return switch (photo) {
      AsyncData(:final value) => PhotoThumb(image: MemoryImage(value), size: size, onRemove: onRemove),
      AsyncError() => _Placeholder(size: size, icon: Icons.broken_image_rounded),
      _ => _Placeholder(size: size, icon: Icons.image_rounded, loading: true),
    };
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size, required this.icon, this.loading = false});

  final double size;
  final IconData icon;
  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: AppColors.violetSoft, borderRadius: BorderRadius.circular(18)),
    alignment: Alignment.center,
    child: loading
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Icon(icon, color: AppColors.violet),
  );
}

/// The "add a photo" tile shown after the thumbnails.
class AddPhotoTile extends StatelessWidget {
  const AddPhotoTile({super.key, required this.onTap, this.size = 84, this.busy = false});

  final VoidCallback? onTap;
  final double size;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add a photo of what you are studying',
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.violetSoft.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.violet.withValues(alpha: 0.35), width: 1.6),
          ),
          child: busy
              ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)))
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_rounded, color: AppColors.violet),
                    const SizedBox(height: 4),
                    Text(
                      'Add',
                      style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.violet),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

Future<void> showPhotoViewer(BuildContext context, ImageProvider image) => showDialog<void>(
  context: context,
  barrierColor: Colors.black87,
  builder: (context) => Stack(
    children: [
      Positioned.fill(
        child: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image(image: image, fit: BoxFit.contain),
          ),
        ),
      ),
      Positioned(
        top: MediaQuery.paddingOf(context).top + 8,
        right: 12,
        child: IconButton.filled(
          tooltip: 'Close',
          style: IconButton.styleFrom(backgroundColor: Colors.white24),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
      ),
    ],
  ),
);
