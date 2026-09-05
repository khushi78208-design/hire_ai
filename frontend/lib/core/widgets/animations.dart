import 'package:flutter/material.dart';

/// Fades and lifts a list item into place. The stagger is what makes a list
/// feel like it arrived rather than blinked.
class FadeInItem extends StatefulWidget {
  final Widget child;
  final int index;

  const FadeInItem({super.key, required this.child, this.index = 0});

  @override
  State<FadeInItem> createState() => _FadeInItemState();
}

class _FadeInItemState extends State<FadeInItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void initState() {
    super.initState();

    // Cap the stagger: on a long list the last card should not wait a
    // second and a half to appear.
    final delay = Duration(milliseconds: (widget.index.clamp(0, 8)) * 55);
    Future.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}

/// Shrinks slightly while held. Cheap to add, and it makes taps feel
/// answered rather than swallowed.
class PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  const PressableCard({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
  });

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.975 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A score as a ring that fills, with the number counting up to meet it.
/// This is the one number a recruiter looks at first, so it earns the
/// extra attention.
class AnimatedScoreRing extends StatelessWidget {
  final int score;
  final Color color;
  final double size;

  const AnimatedScoreRing({
    super.key,
    required this.score,
    required this.color,
    this.size = 58,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score / 100),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  backgroundColor: theme.dividerColor,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Text(
                '${(value * 100).round()}',
                style: TextStyle(
                  fontSize: size * 0.32,
                  fontWeight: FontWeight.w600,
                  height: 1,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Grey blocks in the shape of the content that is coming. Better than a
/// spinner when a cold start means waiting the better part of a minute.
class SkeletonCard extends StatefulWidget {
  const SkeletonCard({super.key});

  @override
  State<SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final shade = Color.lerp(
          theme.dividerColor,
          theme.colorScheme.surfaceContainerHighest,
          _c.value,
        )!;

        Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: shade,
            borderRadius: BorderRadius.circular(6),
          ),
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: shade,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(120, 13),
                      const SizedBox(height: 7),
                      bar(80, 11),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              bar(double.infinity, 11),
              const SizedBox(height: 7),
              bar(220, 11),
            ],
          ),
        );
      },
    );
  }
}

/// A page route that slides in from the right instead of the platform
/// default, so navigation reads the same everywhere.
Route<T> slideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
  );
}
