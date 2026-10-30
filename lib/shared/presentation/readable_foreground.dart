import 'package:flutter/material.dart';

/// Choose the higher-contrast text/selection color for a painted background.
/// The caller composites transparent fills before painting and calling this.
Color readableForeground(Color opaqueBackground) {
  final luminance = opaqueBackground.computeLuminance();
  final blackContrast = (luminance + 0.05) / 0.05;
  final whiteContrast = 1.05 / (luminance + 0.05);
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}
