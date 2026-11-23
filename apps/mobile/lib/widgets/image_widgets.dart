import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

enum ImageAction { gallery, camera, remove }

/// Bottom sheet: choose from gallery, take a photo, or (optionally) remove the current image.
Future<ImageAction?> showImageSourceSheet(BuildContext context, {bool canRemove = false, String removeLabel = 'Remove image'}) {
  return showModalBottomSheet<ImageAction>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery', style: AppText.bodyStrong),
            onTap: () => Navigator.pop(ctx, ImageAction.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo', style: AppText.bodyStrong),
            onTap: () => Navigator.pop(ctx, ImageAction.camera),
          ),
          if (canRemove)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              title: Text(removeLabel, style: AppText.bodyStrong.copyWith(color: AppColors.danger)),
              onTap: () => Navigator.pop(ctx, ImageAction.remove),
            ),
          const SizedBox(height: AppSpace.s8),
        ],
      ),
    ),
  );
}

ImageSource sourceFor(ImageAction a) => a == ImageAction.camera ? ImageSource.camera : ImageSource.gallery;

/// A slide's picture: rounded, height-capped, with a quiet placeholder while it loads and
/// nothing at all if it can't be loaded (the question still works without it).
class SlideImage extends StatelessWidget {
  const SlideImage(this.url, {super.key, this.maxHeight = 220});

  final String url;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Image.network(
          url,
          key: const ValueKey('slide-image'),
          fit: BoxFit.contain,
          width: double.infinity,
          semanticLabel: 'Slide image',
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : Container(
                  height: maxHeight * 0.6,
                  color: AppColors.bgApp,
                  alignment: Alignment.center,
                  child: const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                ),
          errorBuilder: (context, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Circle avatar: the lecturer's photo, or their initials.
class LecturerAvatar extends StatelessWidget {
  const LecturerAvatar({super.key, required this.name, this.url, this.size = 40, this.busy = false});

  final String name;
  final String? url;
  final double size;
  final bool busy;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = Center(
      child: Text(_initials, style: AppText.bodyStrong.copyWith(color: AppColors.brand, fontSize: size * 0.38)),
    );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipOval(
            child: ColoredBox(
              color: AppColors.brandTint,
              child: url == null
                  ? initials
                  : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => initials),
            ),
          ),
          if (busy)
            const ClipOval(
              child: ColoredBox(
                color: Color(0x88FFFFFF),
                child: Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.5))),
              ),
            ),
        ],
      ),
    );
  }
}
