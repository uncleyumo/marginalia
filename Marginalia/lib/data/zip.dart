// A minimal zip reader for ONE stored member.
//
// Dart's core has no zip decoder and `archive` is not a dependency of this
// project, so this reads the central directory and inflates a single deflated
// member with `ZLibCodec`. That is all the dictionary needs:
// `tools/build_dictionary.py` writes an archive containing exactly one file.
//
// Deliberately free of any Flutter import. That is not purity for its own sake
// — it is what lets `tool/check_dictionary.dart` run this decoder against the
// real 10.4 MB archive in a plain Dart VM, where a `package:flutter` import
// would drag in `dart:ui` and fail. The riskiest hand-written code in the
// project therefore has a test that actually exercises it.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class Archive {
  Archive(this.files);

  final List<ZipEntry> files;
}

class ZipEntry {
  ZipEntry(this.name, this.content);

  final String name;
  final List<int> content;
}

class ZipDecoder {
  ZipDecoder(this.bytes)
      : _view = ByteData.sublistView(Uint8List.fromList(bytes));

  final List<int> bytes;
  final ByteData _view;

  /// Decode the first member. Throws a [StateError] with a specific message
  /// rather than returning something empty, because a silently empty dictionary
  /// would look to the user like "this app has no words in it".
  Archive decode() {
    // End of central directory: signature 0x06054b50, scanned backwards. The
    // record sits at the very end unless there is a trailing comment, hence the
    // 64 KB window.
    int eocd = -1;
    for (int i = bytes.length - 22; i >= 0 && i >= bytes.length - 66000; i--) {
      if (_u32(i) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) {
      throw StateError('not a zip archive: no end-of-central-directory record');
    }

    final int count = _u16(eocd + 10);
    int offset = _u32(eocd + 16);
    if (offset == 0) {
      throw StateError('zip has no central directory entry');
    }
    // A single-member archive is what this decoder supports. Saying so up front
    // is clearer than looping over a count the loop then ignores.
    if (count < 1) {
      throw StateError('zip central directory is empty');
    }

    for (int i = 0; i < count; i++) {
      if (_u32(offset) != 0x02014b50) break;
      final int method = _u16(offset + 10);
      final int compressedSize = _u32(offset + 20);
      final int nameLen = _u16(offset + 28);
      final int localOffset = _u32(offset + 42);
      final String name = utf8.decode(
        bytes.sublist(offset + 46, offset + 46 + nameLen),
        allowMalformed: true,
      );

      // The local header repeats the name and extra lengths, and they can
      // differ from the central ones, so the data offset must be recomputed
      // here rather than reused.
      final int localNameLen = _u16(localOffset + 26);
      final int localExtraLen = _u16(localOffset + 28);
      final int dataStart = localOffset + 30 + localNameLen + localExtraLen;
      final List<int> content =
          bytes.sublist(dataStart, dataStart + compressedSize);

      final List<int> out;
      if (method == 0) {
        out = content; // stored
      } else if (method == 8) {
        out = ZLibCodec(raw: true).decode(content); // deflate
      } else {
        throw StateError('unsupported zip compression method $method');
      }
      // The first member is the whole archive as far as this app is concerned.
      return Archive(<ZipEntry>[ZipEntry(name, out)]);
    }
    throw StateError('zip central directory is unreadable');
  }

  int _u16(int at) => _view.getUint16(at, Endian.little);
  int _u32(int at) => _view.getUint32(at, Endian.little);
}
