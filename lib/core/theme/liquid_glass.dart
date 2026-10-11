import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Reusable clean solid surface containers for the Fresh Cane UI (liquid glass removed).
class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double blurSigma;
  final Color? tintColor;
  final Color? borderColor;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final bool showBorder;
  final bool showShadow;
  final BoxConstraints? constraints;
  final AlignmentGeometry? alignment;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.blurSigma = 0,
    this.tintColor,
    this.borderColor,
    this.borderRadius = AppColors.radiusMedium,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.showBorder = true,
    this.showShadow = true,
    this.constraints,
    this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      constraints: constraints,
      alignment: alignment,
      padding: padding,
      decoration: BoxDecoration(
        color: tintColor ?? AppColors.cardSurface,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showShadow ? AppColors.shadowSmall : null,
        border: showBorder
            ? Border.all(
                color: borderColor ?? AppColors.borderLight,
                width: 1.0,
              )
            : null,
      ),
      child: child,
    );
  }
}

/// A card with clean solid surface styling (liquid glass removed).
class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final double blurSigma;
  final Color? tintColor;
  final Color? borderColor;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.blurSigma = 0,
    this.tintColor,
    this.borderColor,
    this.borderRadius = AppColors.radiusLarge,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: tintColor ?? AppColors.cardSurface,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: AppColors.shadowMedium,
        border: Border.all(
          color: borderColor ?? AppColors.borderLight,
          width: 1.0,
        ),
      ),
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: card,
        ),
      );
    }

    return card;
  }
}

/// A subtle solid navbar / header bar (liquid glass removed).
class LiquidGlassBar extends StatelessWidget {
  final Widget child;
  final double height;
  final EdgeInsetsGeometry? padding;
  final Color? tintColor;
  final double blurSigma;

  const LiquidGlassBar({
    super.key,
    required this.child,
    this.height = 58,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.tintColor,
    this.blurSigma = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: tintColor ?? AppColors.cardSurface,
        border: const Border(
          bottom: BorderSide(color: AppColors.borderLight, width: 1),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Decorative status pill / badge.
class GlassStatusBadge extends StatelessWidget {
  final String label;
  final Color foregroundColor;
  final Color backgroundColor;
  final IconData? icon;

  const GlassStatusBadge({
    super.key,
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: foregroundColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foregroundColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}
