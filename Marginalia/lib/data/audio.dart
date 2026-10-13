// Making the sound.
//
// Two engines and no silent retry between them, because that is the design: the
// device's own text-to-speech is the floor, and MiMo is the one online engine.
// The app never changes voice behind the reader's back — it says which one is
// speaking on the Listen screen, every time.
//
// Three bugs lived here and all three are fixed below rather than worked around:
//
//   - The player used to speak a `pendingText` field the Listen screen never
//     set, so every sentence on that screen reached the engine as an empty
//     string: silence, behind a play button that looked alive. The text is now
//     an ARGUMENT of `play()`, and there is no field left to forget.
//   - `flutter_tts` was asked to pause and resume, and neither is reliable
//     across platforms. Resume now re-speaks from the start of the sentence,
//     which is what actually happens and what the screen says.
//   - A recording that would not play used to end the sentence. It now falls
//     through to the device voice, and the label changes to match.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'remote/api.dart';

/// Which engine is speaking. The UI reads this to label itself honestly.
enum VoiceSource {
  /// A pre-built recording from MiMo.
  recorded,

  /// The phone's own text-to-speech.
  device,
}

extension VoiceSourceX on VoiceSource {
  bool get isRecorded => this == VoiceSource.recorded;

  /// Spoken in the reader's language. The Listen screen shows this verbatim
  /// rather than implying a recording exists when none does.
  String get label => this == VoiceSource.recorded
      ? 'a recorded voice · MiMo · online · free'
      : "the phone's own voice · free · offline · airplane mode";

  String get storageId => this == VoiceSource.recorded ? 'mimo' : 'device';
}

/// What the device engine can actually do on THIS phone.
///
/// Checked rather than assumed. A phone with no speech engine installed is a
/// perfectly ordinary phone, and the honest thing is to say so on the Settings
/// screen instead of leaving the reader pressing a button that does nothing.
class DeviceVoice {
  const DeviceVoice({required this.available, required this.note});

  final bool available;
  final String note;
}

/// What a view needs from whatever is making the sound.
///
/// An interface rather than a concrete class so the widgets never learn which
/// engine answered, and so the sentence screen can be reasoned about without
/// opening this file.
abstract class SentencePlayer {
  /// Speak [text], which belongs to sentence [index], and return when it has
  /// finished or been stopped.
  Future<void> play(int index, String text);

  Future<void> stop();

  /// Start narrating [articleId].
  ///
  /// This is where a Random roll happens — once per article, not once per
  /// sentence. See [SentenceAudio.narrate].
  void narrate(String articleId);

  /// Begin building [text] into the recording cache WITHOUT playing it.
  ///
  /// Returns immediately; the work happens in the background. This is the
  /// whole of the TTS latency strategy: while sentence N is speaking, N+1 is
  /// already being synthesised, so the join between them is a file open
  /// instead of a network round-trip. A no-op when there is no recorded voice
  /// to build with — the device engine has nothing to prepare.
  void warm(String text);

  /// Drop everything queued but not yet started.
  ///
  /// Tapping "next" twenty times must not synthesise the nineteen sentences
  /// the listener skipped past. Called when the reader moves somewhere else;
  /// [stop] deliberately does NOT do this, because [play] stops before every
  /// sentence and would throw away its own warm-up.
  void abandonPending();

  /// Pause. There is no portable resume that continues mid-word, so [resume]
  /// re-speaks from the start of the sentence — stated on screen, not hidden.
  Future<void> pause();

  Future<void> resume();

  bool get isPlaying;

  VoiceSource get source;

  bool get hasRecordedAudio;
}

class SentenceAudio implements SentencePlayer {
  SentenceAudio({FlutterTts? tts, ja.AudioPlayer? player, RemoteApi? api})
      : _tts = tts ?? FlutterTts(),
        _player = player ?? ja.AudioPlayer(),
        _api = api ?? RemoteApi();

  final FlutterTts _tts;
  final ja.AudioPlayer _player;
  final RemoteApi _api;

  /// The one-time engine setup, awaited before the first word is spoken.
  ///
  /// It used to be fired and forgotten from the constructor body, so
  /// `setLanguage('en-US')` and `awaitSpeakCompletion(true)` raced the first
  /// `speak()` — a sentence could come out in the phone's default language, or
  /// the completion callback could arrive too late and the next sentence start
  /// on top of it. A `late final` future is the whole fix: every path that
  /// speaks awaits it first, and it still runs exactly once.
  late final Future<void> _ttsReady = _configureTts();

  Completer<void>? _current;
  String _currentText = '';

  /// What the reader CHOSE. Only [configure] writes this.
  VoiceSource _configured = VoiceSource.device;

  /// What actually spoke last.
  ///
  /// A recording that fails falls through to the device engine, and the Listen
  /// screen has to label what the reader is actually hearing — so this moves on
  /// its own. The previous version wrote the fallback into the configured field
  /// instead, so ONE dropped request turned MiMo off permanently for the rest of
  /// the session and the label never went back.
  VoiceSource _lastSpoken = VoiceSource.device;

  DeviceVoice _device = const DeviceVoice(
      available: true, note: 'this phone has an English voice installed');

  String _apiKey = '';
  String _baseUrl = VoiceEndpoint.mimo.baseUrl;
  String _voice = VoiceEndpoint.mimo.voices.first;

  /// The concrete voice id that will actually be sent to the API.
  ///
  /// Equal to [_voice] unless the reader picked [kVoiceRandom]. Random is a
  /// MODE, not an id: the API would reject it. One roll covers a whole
  /// article, so every sentence is spoken by the same narrator — a voice that
  /// changed sentence to sentence would make the piece unlistenable, and a
  /// voice that changes between articles is the variety Random is for.
  /// The roll lives in [narrate], not in [stop]: [play] stops the previous
  /// sentence on every call, so rolling there would re-roll per sentence.
  String _speakingAs = VoiceEndpoint.mimo.voices.first;

  bool _sessionReady = false;

  @override
  bool get isPlaying => _current != null;

  /// What is speaking, not what was asked for. The two differ exactly when a
  /// recording failed, and that is the moment the reader most needs the truth.
  @override
  VoiceSource get source => _lastSpoken;

  @override
  bool get hasRecordedAudio => _configured == VoiceSource.recorded;

  DeviceVoice get deviceVoice => _device;

  /// Point the player at an engine. Called at boot and whenever Settings
  /// changes, so neither screen has to know how the other one was configured.
  void configure({
    required VoiceSource source,
    String apiKey = '',
    String baseUrl = '',
    String voice = '',
  }) {
    _configured = source;
    // Optimistic until proven otherwise: the label should name the engine the
    // reader asked for until one actually fails to answer.
    _lastSpoken = source;
    _apiKey = apiKey.trim();
    if (baseUrl.trim().isNotEmpty) _baseUrl = baseUrl.trim();
    if (voice.trim().isNotEmpty) {
      _voice = voice.trim();
      // A mode change takes effect on the article that is open now, not on the
      // next one. `articleId` is '' here because no article is being narrated
      // yet — the next `narrate` will resolve properly.
      _speakingAs = _resolveVoice(_voice, '');
    }
  }

  /// Roll a real id for [kVoiceRandom], or pass the id through.
  ///
  /// Random excludes itself and nothing else: `mimo_default` is a real voice
  /// and is a fine pick. The choice is DETERMINISTIC in [articleId] rather
  /// than drawn from a clock: the recording cache is keyed on voice + text, so
  /// a voice that could differ between runs would make every replay a fresh
  /// batch of TTS requests and a fresh pile of orphaned wav files. Hashing the
  /// article gives variety across articles and a stable narrator within one.
  static String _resolveVoice(String wanted, String articleId) {
    if (wanted != kVoiceRandom) return wanted;
    final List<String> real = VoiceEndpoint.mimo.voices;
    if (real.isEmpty) return 'mimo_default';
    return real[int.parse(_hash(articleId), radix: 16) % real.length];
  }

  /// Start narrating [articleId]. The ONE place the Random choice is applied.
  ///
  /// Called when an article opens, which is the boundary the choice belongs
  /// on: one article, one narrator. Resolving inside [stop] looked equivalent
  /// and was not — [play] stops the previous sentence on every call, so the
  /// narrator was re-resolved sentence by sentence and the piece became
  /// unlistenable. The same article always resolves to the same voice, so a
  /// sentence tapped on the Read screen, the Listen screen and a second
  /// listen next week all agree on who is speaking.
  @override
  void narrate(String articleId) {
    _speakingAs = _resolveVoice(_voice, articleId);
  }

  /// Set the engine up once. Called from the constructor and not awaited: nothing
  /// may speak until the reader asks, and by then this has long finished. A
  /// failure is recorded rather than thrown — a phone that refuses to be
  /// configured still has to open.
  Future<void> _configureTts() async {
    try {
      await _tts.setLanguage('en-US');
      // The prototype is explicit that this is an American app: spelling, usage,
      // IPA and voices are all en-US, so the voice must match.
      await _tts.setSpeechRate(0.44);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      // Stop rather than roll on: a sentence that bleeds into the next one makes
      // a listener lose the thread.
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('tts configure failed: $e');
    }
  }

  /// Ask the phone what it can speak with. Cheap, and the answer is shown on the
  /// Settings screen instead of being discovered by pressing play.
  Future<DeviceVoice> probeDevice() async {
    try {
      final Object? lang = await _tts.isLanguageAvailable('en-US');
      final Object? engines = await _tts.getEngines;
      final bool hasEngine = engines is List && engines.isNotEmpty;
      if (lang == false) {
        _device = DeviceVoice(
          available: false,
          note: hasEngine
              ? 'this phone has no English voice pack installed'
              : 'this phone has no speech engine installed',
        );
      } else if (lang == null && !hasEngine) {
        _device = const DeviceVoice(
          available: false,
          note: 'this phone could not be asked about its voices',
        );
      } else {
        _device =
            const DeviceVoice(available: true, note: 'English is installed');
      }
    } catch (e) {
      _device = const DeviceVoice(
          available: false, note: 'the speech engine refused to answer');
    }
    return _device;
  }

  /// Speak one word. Used by the word sheet's Say it, and it must work with no
  /// key at all — which it does, because the device engine is the floor.
  Future<bool> speakWord(String word, {double rate = 0.42}) async {
    await stop();
    try {
      // The language and the completion flag must be set before the first word,
      // not concurrently with it.
      await _ttsReady;
      await _tts.setSpeechRate(rate);
      await _tts.speak(word);
      await _tts.setSpeechRate(0.44);
      return true;
    } catch (e) {
      debugPrint('speakWord failed: $e');
      return false;
    }
  }

  /// Prove a recorded voice works. Returns null on success, or a sentence the
  /// Settings screen can show verbatim.
  Future<String?> probeMiMo() async {
    try {
      await _api.testVoice(
          baseUrl: _baseUrl, apiKey: _apiKey, voice: _speakingAs);
      return null;
    } on RemoteFailure catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  @override
  Future<void> play(int index, String text) async {
    await stop();
    _currentText = text;
    final Completer<void> done = Completer<void>();
    _current = done;

    // A recorded voice, when one is configured and one can be had. Any failure
    // at all falls THROUGH to the device engine rather than leaving a gap.
    if (_configured == VoiceSource.recorded && _apiKey.isNotEmpty) {
      final String? path = await _cachedRecording(text, urgent: true);
      if (path != null) {
        final bool played = await _playFile(path);
        if (played) {
          _lastSpoken = VoiceSource.recorded;
          _finish(done);
          return;
        }
        // The recording was useless. Say it with the phone's own voice instead,
        // and label it that way — without un-configuring MiMo, which is a
        // decision only the reader gets to make.
        _lastSpoken = VoiceSource.device;
      }
    }

    await _speak(done, text);
  }

  void _finish(Completer<void> done) {
    if (!done.isCompleted) done.complete();
    _current = null;
    _currentText = '';
  }

  Future<void> _speak(Completer<void> done, String text) async {
    try {
      await _ensureSession();
      await _ttsReady;
      // Whichever route got here, this is the phone speaking.
      _lastSpoken = VoiceSource.device;
      await _tts.speak(text);
    } catch (e) {
      debugPrint('tts speak failed: $e');
      _device = const DeviceVoice(
        available: false,
        note: 'the speech engine refused to speak',
      );
    }
    _finish(done);
  }

  /// MiMo's answer, written to disk once and reused forever after.
  ///
  /// A synthesised sentence is a fact about the phone, not about the network:
  /// hearing it again must not cost another request. So the cache is keyed by
  /// the voice AND the exact words, and a hit never touches the network at all.
  Future<String?> _cachedRecording(String text,
      {bool urgent = false, int? epoch}) async {
    final File file = await _recordingFile(text);
    if (file.existsSync() && file.lengthSync() > 1024) return file.path;

    // Already on the wire or already claimed: join it rather than paying for
    // the same sentence twice and racing two writers at one `.part` file.
    final Future<String?>? inflight = _inflight[text];
    if (inflight != null) return inflight;

    // Gate and epoch check come BEFORE claiming the memo, and that order is
    // the whole correctness argument. An abandoned warm must never occupy the
    // memo slot: a `play` arriving at the same sentence would otherwise join
    // a future that is about to complete as `null` and fall through to the
    // device voice for a recording that was never made.
    await _acquireSynth(urgent: urgent);
    // Re-check after the wait. A sentence that queued behind a full pipe can
    // find, when it finally gets a slot, that the reader has skipped past it.
    // Only warm work carries an epoch — a play is always wanted, because
    // somebody is sitting through silence waiting for exactly that sentence.
    if (epoch != null && epoch != _warmEpoch) {
      _releaseSynth();
      return null;
    }
    final Future<String?>? raced = _inflight[text];
    if (raced != null) {
      // Somebody claimed it while we waited on the gate. Their slot covers
      // the request; ours goes back.
      _releaseSynth();
      return raced;
    }

    final Future<String?> job = _speakToCache(file, text);
    _inflight[text] = job;
    unawaited(job.whenComplete(() {
      _inflight.remove(text);
      _releaseSynth();
    }));
    return job;
  }

  /// The network call and the write to disk. No gating here — see
  /// [_cachedRecording], which owns the gate and the memo.
  Future<String?> _speakToCache(File file, String text) async {
    try {
      final List<int> bytes = await _api.speak(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        text: text,
        voice: _speakingAs,
      );
      await file.parent.create(recursive: true);
      final File tmp = File('${file.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      return file.path;
    } on RemoteFailure catch (e) {
      debugPrint('MiMo did not speak: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('MiMo recording failed: $e');
      return null;
    }
  }

  /// Requests already on the wire, keyed by the same string as the cache file.
  final Map<String, Future<String?>> _inflight = <String, Future<String?>>{};

  /// Sentences waiting for a synthesise slot, next-to-play first.
  ///
  /// A queue rather than a free-for-all on purpose: tapping "next" through a
  /// piece enqueues every sentence passed over, and those must not become one
  /// HTTP request each all at once. The cap is on REQUESTS IN FLIGHT, not on
  /// how much is queued — queueing is free, requests are not.
  final List<String> _warmQueue = <String>[];

  /// How many synthesises may touch the network at once.
  ///
  /// One is polite but leaves the pipe idle while a long sentence plays; three
  /// is enough that one slow request holds up the whole queue behind it. Two
  /// sits between them.
  static const int _maxConcurrentSynth = 2;
  int _synthInFlight = 0;

  /// Callers parked waiting for a slot. FIFO, and `play` is pushed to the
  /// FRONT because it is the one a listener is sitting through silence for.
  final List<({Completer<void> gate, bool urgent})> _synthWaiters =
      <({Completer<void> gate, bool urgent})>[];

  /// Bumped when the reader moves somewhere else, so queued work that is no
  /// longer next can be dropped instead of paid for.
  int _warmEpoch = 0;

  /// Take a synthesise slot, waiting if the pipe is full.
  Future<void> _acquireSynth({bool urgent = false}) async {
    if (_synthInFlight < _maxConcurrentSynth) {
      _synthInFlight++;
      return;
    }
    final Completer<void> gate = Completer<void>();
    _synthWaiters.add((gate: gate, urgent: urgent));
    if (urgent && _synthWaiters.length > 1) {
      // Jump the line: the listener is waiting on THIS one.
      _synthWaiters
        ..removeLast()
        ..insert(0, (gate: gate, urgent: true));
    }
    await gate.future;
  }

  void _releaseSynth() {
    while (_synthWaiters.isNotEmpty) {
      final ({Completer<void> gate, bool urgent}) next = _synthWaiters.removeAt(0);
      // The slot is transferred rather than returned to the counter, so a
      // waiter wakes already holding it and nobody else can steal it in
      // between.
      if (!next.gate.isCompleted) {
        next.gate.complete();
        // A freed slot may let the warm queue move again. Without this kick a
        // pair of `play` requests that held both slots would leave whatever
        // was queued behind them stalled forever.
        unawaited(_drainWarm());
        return;
      }
    }
    _synthInFlight--;
    unawaited(_drainWarm());
  }

  @override
  void warm(String text) {
    // Nothing to prepare for the device engine, and nothing to prepare when
    // there is no key — both cases speak live and cost nothing to 'miss'.
    if (_configured != VoiceSource.recorded || _apiKey.isEmpty) return;
    if (_inflight.containsKey(text) || _warmQueue.contains(text)) return;
    // The sentence about to play matters more than one queued when the
    // listener was still three sentences back, so newest intent goes to the
    // FRONT and the queue drains from the front.
    _warmQueue.insert(0, text);
    unawaited(_drainWarm());
  }

  @override
  void abandonPending() {
    // The reader jumped. What was queued was queued for a moment that has
    // gone. Requests already in flight are kept: those bytes are paid for and
    // the cache will use them whenever the sentence comes round again.
    _warmEpoch++;
    _warmQueue.clear();
  }

  Future<void> _drainWarm() async {
    while (_warmQueue.isNotEmpty && _synthInFlight < _maxConcurrentSynth) {
      final String text = _warmQueue.removeAt(0);
      final int epoch = _warmEpoch;
      // Re-check AFTER the dequeue: a jump while we were waiting makes this a
      // sentence nobody wants any more. Dropping here is the whole point of
      // the epoch — the request that would have been paid for never starts.
      if (epoch != _warmEpoch) continue;
      unawaited(_cachedRecording(text, urgent: false, epoch: epoch));
    }
  }

  Future<File> _recordingFile(String text) async {
    final Directory base = await getApplicationSupportDirectory();
    final Directory dir = Directory(p.join(base.path, 'voice'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, '${_hash('$_speakingAs|$text')}.wav'));
  }

  /// FNV-1a. Short, stable, and good enough to tell two sentences apart — this is
  /// a cache key, not a security primitive.
  static String _hash(String s) {
    int h = 0x811c9dc5;
    for (final int b in utf8.encode(s)) {
      h ^= b;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  Future<bool> _playFile(String path) async {
    try {
      await _ensureSession();
      await _player.setFilePath(path);
      await _player.play();
      await _player.processingStateStream.firstWhere(
        (ja.ProcessingState s) =>
            s == ja.ProcessingState.completed ||
            s == ja.ProcessingState.idle,
      );
      return true;
    } catch (e) {
      debugPrint('recorded audio failed, using the device voice: $e');
      return false;
    }
  }

  Future<void> _ensureSession() async {
    if (_sessionReady) return;
    _sessionReady = true;
    try {
      // Speech, not music: this must keep playing with the screen off and be
      // routed as speech on a headset.
      final AudioSession session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    } catch (e) {
      debugPrint('audio session unavailable: $e');
    }
  }

  @override
  Future<void> stop() async {
    final Completer<void>? c = _current;
    _current = null;
    _currentText = '';
    // No voice roll here. `play` calls `stop` before every sentence, so a roll
    // in this method re-rolled the narrator sentence by sentence — which is
    // the bug where Random made an article unlistenable. The roll lives in
    // [narrate], which fires once per article.
    try {
      await _tts.stop();
    } catch (_) {
      // Stopping something that is not speaking is not an error.
    }
    // `PlayerState` is a CLASS in just_audio 0.10, not an enum — `idle` lives on
    // `ProcessingState`. Checking the wrong one is a compile error rather than a
    // silent wrong answer, which is the good kind of version difference.
    try {
      if (_player.processingState != ja.ProcessingState.idle) {
        await _player.stop();
      }
    } catch (_) {
      // Nothing loaded, so nothing to stop.
    }
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<void> pause() async {
    try {
      await _tts.pause();
    } catch (_) {
      // Not every device engine has pause.
    }
    try {
      await _player.pause();
    } catch (_) {
      // As above.
    }
  }

  @override
  /// Re-speak the current sentence from its start.
  ///
  /// There is no portable mid-word resume, so this is what "resume" means here —
  /// and the Listen screen says so. It is deliberately NOT the Listen screen's
  /// play button: after the last sentence, [stop] has cleared the text, so this
  /// returns immediately and a button wired to it would look alive and do
  /// nothing. The screen restarts the sentence through [play] instead.
  Future<void> resume() async {
    if (_currentText.isEmpty) return;
    if (_configured == VoiceSource.recorded && _apiKey.isNotEmpty) {
      final String? path = await _cachedRecording(_currentText, urgent: true);
      if (path != null && await _playFile(path)) {
        _lastSpoken = VoiceSource.recorded;
        return;
      }
    }
    try {
      await _ttsReady;
      _lastSpoken = VoiceSource.device;
      await _tts.speak(_currentText);
    } catch (_) {
      // Nothing left to try; the sentence stays visible on screen.
    }
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _player.dispose();
    } catch (_) {}
    _api.close();
  }
}