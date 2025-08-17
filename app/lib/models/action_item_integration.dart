import 'package:flutter/material.dart';

/// Enumeration of possible export destinations for action items.
///
/// Each value defines a human‑readable [displayName] and optionally an
/// asset name or fallback [icon]. The `assetPath` and `isSvg` fields
/// describe an optional image resource; however, because the asset files for
/// Apple Calendar and Apple Notes logos are not included in this patch, we
/// leave these fields null and rely on the provided [icon] instead. When
/// [assetPath] is non‑null, [fullAssetPath] prefixes it with
/// `assets/images/` for use with `Image.asset` or `SvgPicture.asset`.
enum ActionItemIntegration {
  appleReminders('Apple Reminders', null, false, Icons.notifications),
  appleNotes('Apple Notes', null, false, Icons.note_outlined),
  appleCalendar('Apple Calendar', null, false, Icons.calendar_today);

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