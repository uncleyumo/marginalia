// Secrets, in this phone's own keystore.
//
// DESIGN §11: a key never leaves the device except to the address the reader
// typed. There is no server in this version — it does not sell a service — so
// there is nothing here that could be sold to someone.
//
// Why a separate file rather than a field on the settings table: the settings
// table is plain SQLite on disk and is read by every query in the app. A key
// must not sit in a table that gets exported, copied or dumped in a bug report.
// The keystore is the one place on Android that is backed by the hardware-backed
// key store, and it is the only place a key is written.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Two keys, and nothing else.
///
/// Both are OPTIONAL. The app is fully usable with neither: the device's own
/// speech engine reads every word and sentence aloud for free and offline, and
/// the writer only runs when the reader taps Write it. A key widens what is
/// possible; it is never a requirement, which is exactly why the startup notice
/// offers a button and does not block.
class KeyStore {
  const KeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// The key that writes articles.
  static const String writerKey = 'writer.api.key';

  /// The key that speaks articles in a recorded voice.
  static const String voiceKey = 'voice.api.key';

  Future<String?> writer() => _read(writerKey);

  Future<String?> voice() => _read(voiceKey);

  Future<void> saveWriter(String value) => _write(writerKey, value);

  Future<void> saveVoice(String value) => _write(voiceKey, value);

  Future<void> clearWriter() => _clear(writerKey);

  Future<void> clearVoice() => _clear(voiceKey);

  /// Whether each capability is actually configured. This is what the startup
  /// notice reads — and it reads the KEY STORE, not a flag: a flag can say
  /// "configured" while the key is gone.
  Future<(bool writer, bool voice)> status() async {
    final String? w = await writer();
    final String? v = await voice();
    return ((w?.trim().isNotEmpty) ?? false, (v?.trim().isNotEmpty) ?? false);
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      // A keystore that refuses to answer is a keystore that says nothing, not
      // one that crashes the app on launch. The reader simply sees "not
      // configured", which is the truth as far as anyone can tell.
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<void> _clear(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Nothing to clear is not a failure worth surfacing.
    }
  }
}