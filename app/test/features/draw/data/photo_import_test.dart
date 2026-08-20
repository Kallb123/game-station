// [downscaleToSheet]'s own bound — a big photo lands on disk no bigger than
// the sheet, aspect ratio kept (`PLAN-phase-8.md` §6 PR 6's own
// done-criterion) — and [ChannelPhotoImport]'s behaviour over a fake
// `zibo/photos` channel: `available` reads `MissingPluginException` the same
// way it would read a handler answering `false` on purpose, which is what
// lets an unbuilt platform's import control simply not appear
// (`photo_import.dart`'s own header).

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/draw/data/photo_import.dart';
import 'package:zibo_games/features/draw/model/stroke.dart'
    show sheetHeight, sheetWidth;

/// A real, decodable PNG of [width] x [height] — solid colour, content does
/// not matter to anything under test here.
Future<Uint8List> _pngOf(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

Future<ui.Image> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('downscaleToSheet', () {
    test(
      'a photo well over the sheet is downscaled to fit inside it',
      () async {
        // 4000 x 3000, `PLAN-phase-8.md` §8's own budget-imported-image size.
        final original = await _pngOf(4000, 3000);

        final downscaled = await downscaleToSheet(original);
        final image = await _decode(downscaled);

        expect(image.width, lessThanOrEqualTo(sheetWidth.round()));
        expect(image.height, lessThanOrEqualTo(sheetHeight.round()));
        // The wider bound (width) is the one that binds for a 4:3 photo
        // against a 4:3 sheet — both should land exactly on it.
        expect(image.width, sheetWidth.round());
        expect(image.height, sheetHeight.round());
      },
    );

    test('aspect ratio survives the downscale', () async {
      // 4000 x 2000 is 2:1 — wider than the sheet's own 4:3 (1600 x 1200,
      // 1.33:1) — so width is the bound that binds first, the same way a
      // panorama would.
      final original = await _pngOf(4000, 2000);

      final downscaled = await downscaleToSheet(original);
      final image = await _decode(downscaled);

      expect(image.width, sheetWidth.round());
      expect(image.height, lessThan(sheetHeight.round()));
      expect((image.width / image.height - 4000 / 2000).abs(), lessThan(0.01));
    });

    test('a photo already within the sheet is not upscaled', () async {
      final original = await _pngOf(400, 300);

      final downscaled = await downscaleToSheet(original);
      final image = await _decode(downscaled);

      expect(image.width, 400);
      expect(image.height, 300);
    });
  });

  group('ChannelPhotoImport.available', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(photoChannel, null);
    });

    test('true when the native side answers true', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(photoChannel, (call) async {
            expect(call.method, 'available');
            return true;
          });

      expect(await const ChannelPhotoImport().available, isTrue);
    });

    test('false when nothing has registered a handler', () async {
      // No `setMockMethodCallHandler` call at all — the same shape of
      // channel a platform with no native side leaves behind
      // (`photo_import.dart`'s own header: `MissingPluginException`).
      expect(await const ChannelPhotoImport().available, isFalse);
    });
  });

  group('ChannelPhotoImport.pick', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(photoChannel, null);
    });

    test('null when the native side answers with nothing chosen', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(photoChannel, (call) async => null);

      expect(await const ChannelPhotoImport().pick(), isNull);
    });

    test('the chosen photo comes back downscaled to fit the sheet', () async {
      final original = await _pngOf(4000, 3000);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(photoChannel, (call) async {
            expect(call.method, 'pick');
            return original;
          });

      final picked = await const ChannelPhotoImport().pick();
      final image = await _decode(picked!);

      expect(image.width, lessThanOrEqualTo(sheetWidth.round()));
      expect(image.height, lessThanOrEqualTo(sheetHeight.round()));
    });
  });
}
