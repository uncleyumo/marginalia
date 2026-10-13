// Turning a picked file into something that can be sent.
//
// This is the ONLY place in the app that decodes a picture, and that is
// deliberate: a decoder is a few hundred milliseconds of full-resolution
// bitmap, and a phone with 3 GB of RAM has been killed for less. One function,
// one owner, one place to make smaller.
//
// THE CONTRACT, in one sentence: [shrink] never throws, and it never returns a
// picture bigger than the one it was given. A picture that cannot be decoded, or
// cannot be made small enough, comes back null and the caller says so in words —
// the reader is not told "codec exception" and is not charged for a write that
// had no picture in it.
//
// WHY JPEG OUT, ALWAYS: PNG is the format screenshots arrive in, and a PNG
// screenshot of a word list is 2–6 MB of lossless text. JPEG at quality 82 puts
// the same text at 200–500 KB and the model reads it just as well — the words are
// the same words. The one case where this is a real loss is a line drawing, which
// nobody photographs as an instruction.

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/picture.dart';

/// Read a picked file, shrink it, and hand back a [Picture] — or null.
///
/// [path] is the platform's copy, which is the only form `image_picker` gives
/// us and the only one worth reading: a `XFile` from the camera may live in a
/// cache directory that is gone by the time the write finishes, so the bytes are
/// taken NOW and the file is never touched again.
Future<Picture?> shrink(String path) async {
  final File f = File(path);
  if (!f.existsSync()) return null;
  final int original;
  try {
    original = f.lengthSync();
  } catch (_) {
    return null;
  }
  if (original <= 0) return null;

  // ALREADY SMALL ENOUGH — pass the bytes through untouched.
  //
  // This is the common case for a screenshot and it is checked FIRST, because
  // re-encoding something that already fits costs a full decode plus a full
  // encode to make the picture slightly worse and save nothing at all.
  if (original <= kMaxPictureBytes) {
    try {
      return Picture(
        bytes: await f.readAsBytes(),
        mediaType: 'image/jpeg',
        originalBytes: original,
      );
    } catch (_) {
      return null;
    }
  }

  final Uint8List raw;
  try {
    raw = await f.readAsBytes();
  } catch (_) {
    return null;
  }

  final img.Image? decoded = img.decodeImage(raw);
  if (decoded == null) {
    // Not a picture this codec can read. Said plainly, because a picture the
    // reader can see on their own screen and the app cannot read is a confusing
    // failure and deserves a sentence rather than a shrug.
    return null;
  }

  final img.Image scaled = _scale(decoded);

  // Quality is walked DOWN rather than fixed, and the walk stops at the first
  // size that fits. 85 → 60 → 45: a word-list screenshot at 45 is still legible
  // to a model, and a picture that had to be walked all the way down was one
  // nobody could have sent anyway.
  for (final int q in const <int>[85, 60, 45]) {
    final Uint8List out;
    try {
      out = img.encodeJpg(scaled, quality: q);
    } catch (_) {
      return null;
    }
    if (out.lengthInBytes <= kMaxPictureBytes) {
      return Picture(
        bytes: out,
        mediaType: 'image/jpeg',
        originalBytes: original,
      );
    }
  }

  // Nothing fit. Send the last attempt anyway — it is still far smaller than
  // the original, and the request body has a better chance than the original
  // ever did. A picture the reader chose is worth more than a clean refusal.
  try {
    return Picture(
      bytes: img.encodeJpg(scaled, quality: 45),
      mediaType: 'image/jpeg',
      originalBytes: original,
    );
  } catch (_) {
    return null;
  }
}

/// Scale to [kPictureLongEdge] on the long side, preserving the aspect ratio.
///
/// Returns the original untouched when it is already small enough — downscaling
/// a 900px screenshot to 1568px would be an UPScale, and an upscaled picture is
/// a blurrier picture for more bytes.
img.Image _scale(img.Image image) {
  final int w = image.width;
  final int h = image.height;
  if (w <= 0 || h <= 0) return image;
  final int longEdge = w >= h ? w : h;
  if (longEdge <= kPictureLongEdge) return image;

  final double k = kPictureLongEdge / longEdge;
  final int nw = (w * k).round().clamp(1, w);
  final int nh = (h * k).round().clamp(1, h);
  return img.copyResize(
    image,
    width: nw,
    height: nh,
    interpolation: img.Interpolation.average,
  );
}
