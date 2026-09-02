import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../ble/led_ui_state.dart';

const String kBrandIconAsset = 'assets/branding/android_app_icon.png';
const String kSplashLogoAsset = 'assets/branding/sc_logo_start_w.png';

class SceptronicPalette {
  static const Color background = Color(0xFF050608);
  static const Color panel = Color(0xFF11141C);
  static const Color panelAlt = Color(0xFF171B24);
  static const Color stroke = Color(0xFF273140);
  static const Color primary = Color(0xFF7DE7FF);
  static const Color secondary = Color(0xFFFFB75D);
  static const Color success = Color(0xFF76F7A0);
  static const Color warning = Color(0xFFFFD166);
  static const Color danger = Color(0xFFFF6B6B);
  static const Color muted = Color(0xFF8F9BB3);
}

TextStyle sceptronicDisplayStyle(
  BuildContext context, {
  double size = 26,
  FontWeight weight = FontWeight.w700,
  Color color = Colors.white,
  double letterSpacing = 1.2,
}) {
  return GoogleFonts.orbitron(
    textStyle: Theme.of(context).textTheme.titleLarge,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
  );
}

class SceptronicBackdrop extends StatelessWidget {
  const SceptronicBackdrop({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF050608),
            Color(0xFF090C12),
            Color(0xFF040506),
          ],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: -100,
            left: -40,
            child: _GlowOrb(
              size: 260,
              colors: [
                Color(0x4422D3EE),
                Color(0x0011141C),
              ],
            ),
          ),
          const Positioned(
            top: 180,
            right: -90,
            child: _GlowOrb(
              size: 280,
              colors: [
                Color(0x22FFB75D),
                Color(0x0011141C),
              ],
            ),
          ),
          const Positioned(
            bottom: -120,
            left: 30,
            child: _GlowOrb(
              size: 320,
              colors: [
                Color(0x1639A0FF),
                Color(0x00050608),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.colors,
  });

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}

class SceptronicPanel extends StatelessWidget {
  const SceptronicPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: SceptronicPalette.stroke),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF161A22),
            Color(0xFF10141B),
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 36,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SceptronicDemoBanner extends StatelessWidget {
  const SceptronicDemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: SceptronicPalette.primary.withValues(alpha: 0.1),
        border: Border.all(
          color: SceptronicPalette.primary.withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.science_outlined,
            size: 20,
            color: SceptronicPalette.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DEMO MODE',
                  style: sceptronicDisplayStyle(
                    context,
                    size: 13,
                    color: SceptronicPalette.primary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Virtual Stock A/B are active. No Bluetooth commands are sent.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SceptronicBrandLockup extends StatelessWidget {
  const SceptronicBrandLockup({
    super.key,
    this.compact = false,
    this.showSubtitle = true,
  });

  final bool compact;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 34.0 : 48.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 10 : 14),
          child: Image.asset(
            kBrandIconAsset,
            width: iconSize,
            height: iconSize,
            fit: BoxFit.cover,
          ),
        ),
        SizedBox(width: compact ? 10 : 14),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ScepTRONIC',
                overflow: TextOverflow.ellipsis,
                style: sceptronicDisplayStyle(
                  context,
                  size: compact ? 18 : 28,
                  letterSpacing: compact ? 1.0 : 1.3,
                ),
              ),
              if (showSubtitle)
                Text(
                  'BLE STOCK CONTROL',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: SceptronicPalette.muted,
                        letterSpacing: 1.6,
                      ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class SceptronicMetricTile extends StatelessWidget {
  const SceptronicMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.detail,
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final String? detail;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: SceptronicPalette.panelAlt,
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: SceptronicPalette.muted,
                        letterSpacing: 0.5,
                        fontSize: compact ? 11 : null,
                      ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 10),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontSize: compact ? 18 : null,
                    ),
              ),
            ),
          ),
          if (detail != null && detail!.isNotEmpty) ...[
            SizedBox(height: compact ? 2 : 4),
            Text(
              detail!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SceptronicPalette.muted,
                    fontSize: compact ? 11 : null,
                  ),
              maxLines: compact ? 2 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
            ),
          ],
        ],
      ),
    );
  }
}

class SceptronicStatusPill extends StatelessWidget {
  const SceptronicStatusPill({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

class SceptronicSectionTitle extends StatelessWidget {
  const SceptronicSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: sceptronicDisplayStyle(context, size: 22)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SceptronicPalette.muted,
                  height: 1.35,
                ),
          ),
        ],
      ],
    );
  }
}

class StockPreview extends StatelessWidget {
  const StockPreview({
    super.key,
    required this.sideLabel,
    required this.sideState,
    required this.motionValue,
    this.footer,
    this.compact = false,
  });

  final String sideLabel;
  final LedUiSideState sideState;
  final double motionValue;
  final Widget? footer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final headColor = animatedSegmentColor(
      sideState.top,
      sideState.heartbeatColor,
      motionValue,
      seedOffset: 0,
    );
    final tipColor = animatedSegmentColor(
      sideState.bottom,
      sideState.heartbeatColor,
      motionValue,
      seedOffset: 140,
    );

    return Column(
      children: [
        Text(
          sideLabel,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                letterSpacing: 1.0,
                fontWeight: FontWeight.w800,
                fontSize: compact ? 15 : null,
              ),
        ),
        SizedBox(height: compact ? 8 : 10),
        _ZoneLabel(label: 'Head', accent: headColor),
        SizedBox(height: compact ? 6 : 8),
        _StockNode(color: headColor, compact: compact),
        Container(
          width: compact ? 12 : 14,
          height: compact ? 92 : 112,
          margin: EdgeInsets.symmetric(vertical: compact ? 4 : 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFE9EDF5),
                Color(0xFF8D96A6),
                Color(0xFFE9EDF5),
              ],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Align(
            alignment: Alignment.center,
            child: Container(
              width: compact ? 24 : 28,
              height: compact ? 44 : 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFF0E1218),
                border: Border.all(color: Colors.white10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              SceptronicPalette.success,
                              SceptronicPalette.success.withValues(alpha: 0.35),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 12,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _StockNode(color: tipColor, compact: compact),
        SizedBox(height: compact ? 6 : 8),
        _ZoneLabel(label: 'Tip', accent: tipColor),
        if (footer != null) ...[
          SizedBox(height: compact ? 10 : 12),
          footer!,
        ],
      ],
    );
  }
}

class _ZoneLabel extends StatelessWidget {
  const _ZoneLabel({
    required this.label,
    required this.accent,
  });

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent,
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.55),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                letterSpacing: 0.9,
                color: Colors.white,
                fontSize: 12,
              ),
        ),
      ],
    );
  }
}

class _StockNode extends StatelessWidget {
  const _StockNode({
    required this.color,
    required this.compact,
  });

  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 62 : 82,
      height: compact ? 62 : 82,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 2),
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.98),
            color.withValues(alpha: 0.62),
            const Color(0xFF0F1217),
          ],
          stops: const [0.0, 0.48, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 26,
            spreadRadius: 3,
          ),
        ],
      ),
    );
  }
}

Color animatedSegmentColor(
  LedUiSegmentState segment,
  Color heartbeatColor,
  double motionValue, {
  double seedOffset = 0,
}) {
  switch (segment.mode) {
    case LedMode.off:
      return const Color(0xFF2B323E);
    case LedMode.color:
      return segment.color;
    case LedMode.heartbeat:
      final pulse = 0.35 +
          ((math.sin((motionValue * math.pi * 4) + seedOffset) + 1) / 2) * 0.65;
      return Color.lerp(const Color(0xFF090B0E), heartbeatColor, pulse)!;
    case LedMode.rainbow:
      final hue = ((motionValue * 360) + seedOffset) % 360;
      return HSVColor.fromAHSV(1, hue, 0.85, 1).toColor();
  }
}
