// A picture the reader attached to an instruction.
//
// This exists because of a real habit: you meet a good sentence on a poster, or
// a scene worth describing, or you are halfway through memorising a word list in
// another app and you take a screenshot. All three are things a camera captures
// in two seconds and a keyboard cannot capture at all. So the instruction is not
// only words any more — it is words AND pictures.
//
// THE THREE FACTS THIS TYPE CARRIES, and why each is here:
//
//   1. BYTES. A picture is sent base64'd, which makes it 4/3 larger on the wire.
//      A 12 MP photo is ~4 MB, and five of those is a 27 MB request body that
//      most providers refuse before charging anything. So the bytes are shrunk
//      ONCE, here, at the boundary — and the shrunk copy is the only one that
//      exists afterwards.
//   2. A MEDIA TYPE. The provider needs `data:image/jpeg;base64,…` or it treats
//      the string as a URL and asks a public server for a file that is not there.
//   3. WHETHER IT WAS RESIZED. The card says what it did. A reader who watches a
//      3.8 MB photo become 480 KB before a request is sent has learned
//      something true about where their data went; one who sees a picture appear
//      and disappear has learned nothing.
//
// WHAT IS DELIBERATELY ABSENT: a file path, a file name, an id, a timestamp, a
// database row. A picture instruction is for the ONE write it was attached to.
// It is not saved, not listed, not re-openable, and never outlives the article
// it produced — see `kMaxPictures` for the number and `PicturePack` for the
// collection. Storing pictures would mean a table of blobs nobody can search and
// a gallery of things the reader already has in their own photo app.

import 'dart:convert';
import 'dart:typed_data';

/// How many pictures one instruction may carry.
///
/// Five, because that is what the reader actually brings: a word-list
/// screenshot, a page of a book, a street sign, a menu, a scene. Ten would be
/// a batch job, and a batch job is a different app.
///
/// It is a LIMIT and not a default — an instruction with one picture is the
/// common case and nothing here pretends otherwise.
const int kMaxPictures = 5;

/// The largest a picture may be on the wire, after resizing.
///
/// 2 MB, because that is what the brief asks for and it is also a sane number:
/// a 1568px-long-edge JPEG at quality 82 lands between 180 KB and 700 KB for
/// anything a phone camera produces, so this ceiling is only ever reached by a
/// screenshot of something enormous. What it prevents is the pathological case —
/// a panorama, or a 48 MP shot in RAW-ish JPEG — arriving whole.
const int kMaxPictureBytes = 2 * 1024 * 1024;

/// The longest edge a picture is scaled down to.
///
/// 1568 is not arbitrary: it is the long edge OpenAI's own vision examples use,
/// and every provider this app talks to downscales to roughly that anyway. Doing
/// it on the phone costs the reader nothing, saves the request body, and means
/// the picture that reaches the model is the one the app chose rather than
/// whatever the provider's own resizer made of a 4032px original.
const int kPictureLongEdge = 1568;

/// One picture, already small enough to send.
class Picture {
  const Picture({
    required this.bytes,
    required this.mediaType,
    required this.originalBytes,
  });

  /// The bytes that will be sent. JPEG.
  final Uint8List bytes;

  /// `image/jpeg`. Always JPEG, whatever the source was — see [PicturePack].
  final String mediaType;

  /// How big the file was before this app touched it. Kept ONLY so the card can
  /// say "3.8 MB → 480 KB". It is not sent anywhere.
  final int originalBytes;

  /// The data URL the OpenAI-shaped API wants.
  ///
  /// Base64, not a URL: there is no server to hold the picture and the reader's
  /// photographs are not going to one.
  String get dataUrl => 'data:$mediaType;base64,${base64Encode(bytes)}';

  /// True when this picture was resized rather than passed through. A file
  /// already under the ceiling is sent exactly as it came, which is the whole
  /// point of the check — re-encoding a 200 KB screenshot to save nothing is
  /// work that makes the picture worse and saves nothing.
  bool get wasResized => bytes.lengthInBytes != originalBytes;

  /// `480 KB`, `3.8 MB`. One decimal place, and the unit changes at 1 MB.
  static String size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// The pictures attached to one write.
///
/// A value object rather than a bare `List<Picture>` because the count is a rule
/// and not an accident: [kMaxPictures] is enforced here, once, so no caller can
/// build a seven-picture instruction by forgetting a check.
///
/// The BYTE ceiling is enforced here too, and until 0.4.0+11 it was not
/// enforced anywhere at all. `kMaxPictureBytes` was declared, documented as
/// "the ceiling", and read by nothing — `shrink.dart`'s last fallthrough returns
/// a picture that is still over it, and `_withPictures` handed that straight to
/// `_write`. A 4 MB photograph therefore reached the wire and was billed at its
/// full base64 size, on the one path in this app that costs the most per
/// request. `ARCHITECTURE.md` claimed "both numbers are checked as executable
/// invariants"; one of them was a comment.
class PicturePack {
  const PicturePack._(this.pictures);

  const PicturePack.empty() : this._(const <Picture>[]);

  factory PicturePack.of(Iterable<Picture> pictures) {
    final List<Picture> list = pictures.toList(growable: false);
    if (list.length > kMaxPictures) {
      throw StateError(
          'an instruction carries at most $kMaxPictures pictures, never more; '
          'got ${list.length}');
    }
    for (final Picture p in list) {
      if (p.bytes.length > kMaxPictureBytes) {
        throw StateError(
            'a picture may not exceed $kMaxPictureBytes bytes after resizing; '
            'this one is ${p.bytes.length}');
      }
    }
    return PicturePack._(List<Picture>.unmodifiable(list));
  }

  final List<Picture> pictures;

  int get length => pictures.length;

  bool get isEmpty => pictures.isEmpty;

  bool get isNotEmpty => pictures.isNotEmpty;

  /// How many bytes this will add to the request body, after base64's 4/3.
  ///
  /// Used by the log line and by nothing else: a request size the reader can be
  /// told about is a request size nobody has to guess at.
  int get wireBytes =>
      pictures.fold<int>(0, (int sum, Picture p) => sum + (p.bytes.length ~/ 3 * 4));
}
