// One drawing, as JSON. Sibling to `core/storage/save_codec.dart` and built
// on the same three decisions (`PLAN-phase-8.md` §4.5): strict about types,
// lenient about a missing optional field, and a decode failure is a typed
// exception rather than a crash — `DrawingRepository` turns one into "this
// picture is missing from the gallery" rather than a boot loop
// (`PLAN.md` §5.3, `AGENTS.md`).
//
// A point is written as two numbers rounded to one decimal place rather than
// the `double` `Offset.dx`/`dy` carry, which is `PLAN-phase-8.md` §4.1's
// budget: about 12 bytes a point instead of the seventeen-odd significant
// digits `jsonEncode` would otherwise spend on a value nothing needs back to
// float precision.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import '../model/stroke.dart';

/// The stored JSON is not a drawing this build can read: a missing field, a
/// field of the wrong type, or text that does not parse.
///
/// [DrawingRepository] answers this the way `FileSaveStore` answers a corrupt
/// `save.json` — the file is left alone and the drawing is skipped in the
/// gallery — except the blast radius is one picture rather than a whole
/// profile (`PLAN-phase-8.md` §4.5).
class DrawingFormatException implements Exception {
  const DrawingFormatException(this.message, [this.path = '']);

  /// What was wrong, in a sentence.
  final String message;

  /// Where, as a dotted path from the document root. Empty for the root.
  final String path;

  @override
  String toString() => path.isEmpty
      ? 'DrawingFormatException: $message'
      : 'DrawingFormatException: $path: $message';
}

/// Parses [json] into a [Drawing].
///
/// Throws [DrawingFormatException] if the text is not a drawing this build
/// can read.
Drawing decodeDrawing(String json) {
  final Object? parsed;
  try {
    parsed = jsonDecode(json);
  } on FormatException catch (error) {
    throw DrawingFormatException('not valid JSON (${error.message})');
  }
  return _readDrawing(_map(parsed, ''));
}

/// Renders [drawing] as the text to write to
/// `drawings/<profileId>/<id>.json`.
String encodeDrawing(Drawing drawing) => jsonEncode(_writeDrawing(drawing));

// --- reading ----------------------------------------------------------------

Drawing _readDrawing(Map<String, Object?> raw) {
  final strokesRaw = _list(_required(raw, 'strokes', ''), 'strokes');
  return Drawing(
    id: _string(_required(raw, 'id', ''), 'id'),
    createdAt: _dateTime(_required(raw, 'createdAt', ''), 'createdAt'),
    strokes: [
      for (var i = 0; i < strokesRaw.length; i++)
        _readStroke(_map(strokesRaw[i], 'strokes[$i]'), 'strokes[$i]'),
    ],
    backdrop: raw['backdrop'] == null
        ? null
        : _bytes(raw['backdrop'], 'backdrop'),
  );
}

Stroke _readStroke(Map<String, Object?> raw, String path) {
  final points = _list(_required(raw, 'points', path), _at(path, 'points'));
  if (points.length.isOdd) {
    throw DrawingFormatException(
      'expected an even count of x, y numbers, got ${points.length}',
      _at(path, 'points'),
    );
  }
  if (points.isEmpty) {
    throw DrawingFormatException(
      'a stroke always has at least one point',
      _at(path, 'points'),
    );
  }

  final offsets = <Offset>[];
  for (var i = 0; i < points.length; i += 2) {
    offsets.add(
      Offset(
        _double(points[i], '${_at(path, 'points')}[$i]'),
        _double(points[i + 1], '${_at(path, 'points')}[${i + 1}]'),
      ),
    );
  }

  return Stroke(
    colorIndex: _int(
      _required(raw, 'colorIndex', path),
      _at(path, 'colorIndex'),
    ),
    sizeIndex: _int(_required(raw, 'sizeIndex', path), _at(path, 'sizeIndex')),
    points: offsets,
  );
}

// --- writing ----------------------------------------------------------------

Map<String, Object?> _writeDrawing(Drawing drawing) => {
  'id': drawing.id,
  'createdAt': drawing.createdAt.toUtc().toIso8601String(),
  'strokes': [for (final stroke in drawing.strokes) _writeStroke(stroke)],
  if (drawing.backdrop != null) 'backdrop': base64Encode(drawing.backdrop!),
};

Map<String, Object?> _writeStroke(Stroke stroke) => {
  'colorIndex': stroke.colorIndex,
  'sizeIndex': stroke.sizeIndex,
  'points': [
    for (final point in stroke.points) ...[
      _rounded(point.dx),
      _rounded(point.dy),
    ],
  ],
};

double _rounded(double value) {
  final factor = _decimalFactor;
  return (value * factor).round() / factor;
}

const int _decimalFactor = 10; // one decimal place (`PLAN-phase-8.md` §4.1)

// --- typed readers ------------------------------------------------------

String _at(String path, String key) => path.isEmpty ? key : '$path.$key';

Never _fail(String path, String message) =>
    throw DrawingFormatException(message, path);

Object? _required(Map<String, Object?> raw, String key, String path) {
  final value = raw[key];
  if (value == null) _fail(_at(path, key), 'is required');
  return value;
}

Map<String, Object?> _map(Object? value, String path) =>
    value is Map<String, Object?>
    ? value
    : _fail(path, 'expected an object, got ${_typeName(value)}');

List<Object?> _list(Object? value, String path) => value is List<Object?>
    ? value
    : _fail(path, 'expected a list, got ${_typeName(value)}');

String _string(Object? value, String path) => value is String
    ? value
    : _fail(path, 'expected a string, got ${_typeName(value)}');

int _int(Object? value, String path) => value is int
    ? value
    : _fail(path, 'expected an integer, got ${_typeName(value)}');

double _double(Object? value, String path) => switch (value) {
  int() => value.toDouble(),
  double() => value,
  _ => _fail(path, 'expected a number, got ${_typeName(value)}'),
};

DateTime _dateTime(Object? value, String path) {
  final text = _string(value, path);
  try {
    return DateTime.parse(text).toUtc();
  } on FormatException {
    throw DrawingFormatException('"$text" is not an ISO-8601 timestamp', path);
  }
}

Uint8List _bytes(Object? value, String path) {
  final text = _string(value, path);
  try {
    return base64Decode(text);
  } on FormatException {
    throw DrawingFormatException('"$path" is not valid base64', path);
  }
}

String _typeName(Object? value) => switch (value) {
  null => 'null',
  bool() => 'true or false',
  int() => 'an integer',
  double() => 'a fractional number',
  String() => 'a string',
  List<Object?>() => 'a list',
  Map<String, Object?>() => 'an object',
  _ => 'an unexpected value',
};
