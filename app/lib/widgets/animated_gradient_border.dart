import 'package:flutter/material.dart';
import 'package:gradient_borders/gradient_borders.dart';

/// A widget that wraps any child with an animated gradient border
/// providing a subtle pulse effect that makes the interface feel alive
class AnimatedGradientBorder extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final Gradient gradient;
  final double borderWidth;
  final Duration animationDuration;
  final double pulseIntensity;
  final Color backgroundColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const AnimatedGradientBorder({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.gradient = const LinearGradient(colors: [
      Color.fromARGB(127, 208, 208, 208),
      Color.fromARGB(127, 188, 99, 121),
      Color.fromARGB(127, 86, 101, 182),
      Color.fromARGB(127, 126, 190, 236)
    ]),
    this.borderWidth = 1.0,
    this.animationDuration = const Duration(seconds: 2),
    this.pulseIntensity = 0.2,
    this.backgroundColor = Colors.black,
    this.padding,
    this.margin,
  });

  @override
  State<AnimatedGradientBorder> createState() => _AnimatedGradientBorderState();
}

class _AnimatedGradientBorderState extends State<AnimatedGradientBorder> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    // Create opacity animation with ease-in-out curve for smooth transitions
    _opacityAnimation = Tween<double>(
      begin: 1.0 - widget.pulseIntensity,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // Start the infinite pulse animation
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Container(
          padding: widget.padding,
          margin: widget.margin,
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: widget.borderRadius,
            border: GradientBoxBorder(
              gradient: LinearGradient(
                colors: widget.gradient.colors.map((color) {
                  // Apply opacity animation to each gradient color
                  return color.withOpacity(color.opacity * _opacityAnimation.value);
                }).toList(),
                begin: (widget.gradient as LinearGradient).begin,
                end: (widget.gradient as LinearGradient).end,
                stops: (widget.gradient as LinearGradient).stops,
              ),
              width: widget.borderWidth,
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}
