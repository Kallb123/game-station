// A method channel to the platform's own photo picker: one `pick()` call
// returning the chosen image's bytes, downscaled to fit the sheet
// (`PLAN-phase-8.md` §3.3, §4.6).
//
// `PhotoPickerPlugin.kt`, registered by `MainActivity.kt`, is the Android
// side and the only native side this pull request builds. The iOS Swift
// half is left for a later pull request, and needs nothing here to arrive:
// a platform with no native handler registered answers every call on this
// channel with `MissingPluginException`, which [ChannelPhotoImport.available]
// reads exactly the way it would read a handler that answered `false` on
// purpose — so an unbuilt platform's import control simply does not appear
// rather than crashing reaching for a channel nothing answers. `PLAN-phase-8.md`
// §6 PR 6 already calls this shape of gap droppable for the phase as a
// whole; here it is droppable per platform instead.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../model/stroke.dart' show sheetHeight, sheetWidth;

/// Picks one photo from the device library, downscaled to fit the sheet.
abstract interface class PhotoImport {
  /// Whether this platform can pick a photo right now.
  Future<bool> get available;

  /// Prompts the system picker and returns the chosen image, downscaled to
  /// fit [sheetWidth] x [sheetHeight] with its aspect ratio kept and
  /// re-encoded as PNG — or null if the picker was dismissed with nothing
  /// chosen.
  Future<Uint8List?> pick();
}

/// The one channel every platform's native picker answers on.
const MethodChannel photoChannel = MethodChannel('zibo/photos');

/// Android's `PhotoPickerPlugin.kt`, over [photoChannel]
/// (`PLAN-phase-8.md` §3.3).
class ChannelPhotoImport implements PhotoImport {
  const ChannelPhotoImport();

  @override
  Future<bool> get available async {
    try {
      return await photoChannel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<Uint8List?> pick() async {
    final bytes = await photoChannel.invokeMethod<Uint8List>('pick');
    if (bytes == null) return null;
    return downscaleToSheet(bytes);
  }
}

/// Decodes [bytes], downscales to fit inside [sheetWidth] x [sheetHeight]
/// with its aspect ratio kept — never upscaled — and re-encodes as PNG
/// (`PLAN-phase-8.md` §4.6). Downscaling on the way in, not the way out, is
/// what keeps a 12 MP phone photo from costing tens of megabytes of the
/// 64 MB per-profile budget.
///
/// Decodes [bytes] twice: once at natural size to read its dimensions, once
/// at the computed target — simpler than juggling a first frame's disposal
/// across a conditional, and cheap next to a picker dialog a child has just
/// tapped through.
Future<Uint8List> downscaleToSheet(Uint8List bytes) async {
  final naturalCodec = await ui.instantiateImageCodec(bytes);
  final naturalFrame = await naturalCodec.getNextFrame();
  final width = naturalFrame.image.width;
  final height = naturalFrame.image.height;
  naturalFrame.image.dispose();

  final scale = math.min(
    1.0,
    math.min(sheetWidth / width, sheetHeight / height),
  );
  final targetWidth = (width * scale).round();
  final targetHeight = (height * scale).round();

  final codec = scale == 1.0
      ? await ui.instantiateImageCodec(bytes)
      : await ui.instantiateImageCodec(
          bytes,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        );
  final frame = await codec.getNextFrame();
  try {
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    frame.image.dispose();
  }
}
