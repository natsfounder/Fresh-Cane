import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Reusable, fail-safe product photo widget.
/// Renders network image from Supabase storage bucket with smooth loading indicator
/// and an elegant fallback placeholder when no photo is uploaded or if network fails.
class ProductImageWidget extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final IconData fallbackIcon;
  final String? heroTag;

  const ProductImageWidget({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.local_cafe_rounded,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(8);
    final hasUrl = imageUrl != null && imageUrl!.trim().isNotEmpty;

    Widget placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.secondaryGreen.withValues(alpha: 0.08),
        borderRadius: radius,
      ),
      child: Center(
        child: Icon(
          fallbackIcon,
          size: (height != null && height! < 50) ? 20 : 28,
          color: AppColors.secondaryGreen.withValues(alpha: 0.5),
        ),
      ),
    );

    if (!hasUrl) {
      return placeholder;
    }

    Widget imageContent = ClipRRect(
      borderRadius: radius,
      child: Image.network(
        imageUrl!.trim(),
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          final total = loadingProgress.expectedTotalBytes;
          final loaded = loadingProgress.cumulativeBytesLoaded;
          final progress = total != null && total > 0 ? loaded / total : null;
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: radius,
            ),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2,
                  color: AppColors.primaryGreen,
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return placeholder;
        },
      ),
    );

    if (heroTag != null && heroTag!.isNotEmpty) {
      return Hero(
        tag: heroTag!,
        child: imageContent,
      );
    }

    return imageContent;
  }
}
