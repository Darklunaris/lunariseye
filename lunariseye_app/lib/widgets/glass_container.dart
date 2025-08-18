import 'dart:ui';
import 'package:flutter/material.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12.0),
    this.borderRadius = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Color.fromARGB(15, 255, 255, 255),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Color.fromARGB(20, 255, 255, 255)),
            boxShadow: [
              BoxShadow(
                color: Color.fromARGB(64, 0, 0, 0),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
            backgroundBlendMode: BlendMode.overlay,
          ),
          child: child,
        ),
      ),
    );
  }
}
