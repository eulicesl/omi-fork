import 'package:flutter/material.dart';

/// Parses a hex color string (e.g., "#FF5733") to a Flutter Color object.
/// Returns the provided fallback color if parsing fails.
Color parseHexColor(String? hexColor, Color fallbackColor) {
  if (hexColor == null) {
    return fallbackColor;
  }

  try {
    return Color(int.parse(hexColor.replaceFirst('#', '0xFF')));
  } catch (e) {
    debugPrint('Error parsing hex color: $hexColor');
    return fallbackColor;
  }
}
