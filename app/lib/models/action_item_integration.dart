import 'package:flutter/material.dart';

/// Enumeration of possible export destinations for action items.
///
/// Each value defines a human‑readable [displayName] and an asset path
/// for the corresponding icon. The `assetPath` field specifies the image
/// file in the `assets/images/` directory. The `isSvg` field indicates
/// whether the asset is an SVG (currently all are PNG). The [icon] field
/// can be used as a fallback if the asset is not available.
enum ActionItemIntegration {
  appleReminders('Apple Reminders', 'apple-reminders-logo.png', false, null),
  appleNotes('Apple Notes', 'apple-notes-logo.png', false, null),
  appleCalendar('Apple Calendar', 'apple-calendar-logo.png', false, null);

  /// The display name shown in the UI.
  final String displayName;

  /// The relative path to an image asset within the `assets/images` folder.
  /// If null, no image is used and a fallback [icon] is displayed instead.
  final String? assetPath;

  /// Whether the asset is an SVG. Ignored if [assetPath] is null.
  final bool isSvg;

  /// A fallback Material icon to show when no asset is provided.
  final IconData? icon;

  const ActionItemIntegration(
    this.displayName,
    this.assetPath,
    this.isSvg,
    this.icon,
  );

  /// Returns the fully qualified asset path, prefixing [assetPath] with
  /// `assets/images/` if an asset is specified. Returns null otherwise.
  String? get fullAssetPath =>
      assetPath != null ? 'assets/images/$assetPath' : null;

  /// Indicates whether an image asset is defined for this integration.
  bool get hasAsset => assetPath != null;
}