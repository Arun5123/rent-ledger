// Generates the RentLedger launcher mark into `assets/icon/`.
//
// Run from the project root, then let `flutter_launcher_icons` fan the two
// source images out to every platform density:
//
// ```sh
// dart run tool/generate_icon.dart
// dart run flutter_launcher_icons
// ```
//
// The mark is drawn rather than exported from a design tool so it stays exact:
// the colours are the ones in `AppTheme`, and the geometry is described once in
// design coordinates and scaled for each output.
import 'dart:io';

import 'package:image/image.dart' as img;

/// Square canvas every source asset is rendered at.
const int _canvas = 1024;
const double _centre = _canvas / 2;

/// Scale applied to the design geometry for the full-bleed square output.
const double _fullBleedScale = 1.42;

/// Scale applied for Android's adaptive foreground — see the note above.
const double _adaptiveScale = 0.80;

// Brand palette, mirroring `AppTheme`.
final img.Color _field = img.ColorRgba8(0x1B, 0x4D, 0x3E, 255);
final img.Color _glyph = img.ColorRgba8(0xFF, 0xFF, 0xFF, 255);
final img.Color _accent = img.ColorRgba8(0xF4, 0xA3, 0x00, 255);

/// The mark is authored inside a 520 x 584 box centred on the canvas:
/// x 252..772, y 220..804.
///
/// Two scales, because the two consumers crop differently:
///
/// * 1.42 for the full-bleed square. iOS masks its icon with a squircle and
///   Android < 8 shows it straight, so the mark should fill the canvas; this
///   leaves ~9% headroom top and bottom, which is the usual amount.
///
/// * 0.80 for the adaptive foreground. An adaptive layer is a 108dp canvas
///   whose only guaranteed-visible region is the centred 66dp circle, i.e. a
///   radius of `1024 * 66/108 / 2 = 312.9px`. The mark's furthest point from
///   the centre is a corner of that 520 x 584 box, at
///   `sqrt(260^2 + 292^2) = 391.0` design units, so any scale above
///   `312.9 / 391.0 = 0.80` puts the block corners outside the safe circle and
///   a circular launcher mask shears them off. 0.80 is exactly tangent.
///
/// Both outputs are deliberately opaque. The adaptive foreground carries the
/// field colour itself rather than being transparent, which is safe because
/// `adaptive_icon_background` is set to the very same colour — so however a
/// launcher composes, insets or parallaxes the two layers, the result is a
/// uniform field behind the glyph.
void main() {
  final outDir = Directory('assets/icon')..createSync(recursive: true);

  // iOS and pre-Android 8 launchers: solid field, edge to edge.
  final legacy = img.Image(width: _canvas, height: _canvas, numChannels: 4);
  img.fill(legacy, color: _field);
  _draw(legacy, _fullBleedScale);
  _makeOpaque(legacy);
  File('${outDir.path}/icon.png').writeAsBytesSync(img.encodePng(legacy));

  // Android adaptive foreground.
  final foreground = img.Image(width: _canvas, height: _canvas, numChannels: 4);
  img.fill(foreground, color: _field);
  _draw(foreground, _adaptiveScale);
  _makeOpaque(foreground);
  File('${outDir.path}/icon_foreground.png')
      .writeAsBytesSync(img.encodePng(foreground));

  _printPreview(legacy, 'icon.png — full bleed (scale $_fullBleedScale)');
  _printPreview(
    foreground,
    'icon_foreground.png — adaptive (scale $_adaptiveScale)',
  );
}

/// `fillRect`'s rounded-rectangle path writes the correct RGB but always drives
/// alpha to zero, because its alpha maths assumes the raw channel value is
/// normalised — and it bypasses `alphaBlend` entirely. Alpha is therefore
/// restored in a single sweep once all shapes are down.
void _makeOpaque(img.Image image) {
  for (final pixel in image) {
    pixel.a = 255;
  }
}

/// Paints the mark at [scale] about the canvas centre.
void _draw(img.Image image, double scale) {
  int at(double design) => (_centre + (design - _centre) * scale).round();

  void box(
    double x1,
    double y1,
    double x2,
    double y2,
    double radius,
    img.Color color,
  ) {
    img.fillRect(
      image,
      x1: at(x1),
      y1: at(y1),
      x2: at(x2),
      y2: at(y2),
      radius: radius * scale,
      color: color,
      // Every shape is a flat rectangle, so blending would only mix it with the
      // field it sits on. Writing straight to the pixel keeps the punched-out
      // windows the exact field colour instead of a blend of the two.
      alphaBlend: false,
    );
  }

  // Two apartment blocks form a stepped skyline.
  box(252, 220, 500, 620, 26, _glyph);
  box(524, 320, 772, 620, 26, _glyph);

  // Window grids are punched back out in the field colour, so they read as the
  // background showing through — even where that background is transparent
  // the generated adaptive colour matches exactly.
  for (final x in const [290.0, 386.0]) {
    for (final y in const [232.0, 332.0, 432.0, 532.0]) {
      box(x, y, x + 76, y + 76, 16, _field);
    }
  }
  for (final x in const [562.0, 658.0]) {
    for (final y in const [332.0, 432.0, 532.0]) {
      box(x, y, x + 76, y + 76, 16, _field);
    }
  }

  // Ledger entries: three rules of decreasing length beneath the skyline.
  box(252, 664, 772, 700, 18, _accent);
  box(326, 716, 698, 752, 18, _accent);
  box(400, 768, 624, 804, 18, _accent);
}

// --------------------------------------------------------------- self-check

/// Renders a coarse ASCII version of [image] so the composition can be verified
/// without opening the PNG.
void _printPreview(img.Image image, String label) {
  const cols = 56;
  const rows = 28;
  final buffer = StringBuffer('$label\n');
  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < cols; col++) {
      final x = ((col + 0.5) * image.width / cols).floor();
      final y = ((row + 0.5) * image.height / rows).floor();
      buffer.write(_glyphFor(image.getPixel(x, y)));
    }
    buffer.writeln();
  }
  stdout.write(buffer);
}

String _glyphFor(img.Pixel pixel) {
  if (pixel.a < 128) return ' ';
  if (_matches(pixel, 0xF4, 0xA3, 0x00)) return '+';
  if (_matches(pixel, 0xFF, 0xFF, 0xFF)) return '#';
  if (_matches(pixel, 0x1B, 0x4D, 0x3E)) return '.';
  return '?';
}

bool _matches(img.Pixel pixel, int r, int g, int b) =>
    (pixel.r - r).abs() < 40 && (pixel.g - g).abs() < 40 && (pixel.b - b).abs() < 40;
