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
  const DeviceVoice({
    required this.available,
    required this.note,
    this.name = '',
  });

  final bool available;
  final String note;

  /// The voice the engine will actually use, as the platform names it. Empty
  /// until one has been chosen.
  ///
  /// Carried because the Listen screen has to say WHO is speaking, and "the
  /// phone's own voice" is not an answer when the phone has several and the
  /// reader picked a male one. See [_pickDeviceVoice].
  final String name;
}

/// Which engine is narrating THIS article.
///
/// A property of the article, not of a sentence. This is the whole fix for the
/// half-male, half-female article: the fallback used to be decided per sentence,
/// so one dropped request in the middle of a piece swapped the narrator halfway
/// through and nothing on screen said so. Now the choice is made once, when the
/// article starts, and held for all of it.
enum Narrator {
  /// A MiMo recording. `_speakingAs` names which voice.
  recorded,

  /// The phone's own engine, with an explicitly chosen voice.
  device,

  /// Not decided yet — before `narrate` has run for this article.
  unknown,
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

  /// The MiMo voice id actually being sent for the article now narrating.
  String get speakingAs;

  /// Which engine is narrating the article now open. One article, one engine.
  Narrator get narrator;

  /// What the phone's own engine can do, including the voice it will use.
  DeviceVoice get deviceVoice;
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

  /// The TTS model id sent with every synthesis. Empty means the provider
  /// default, so an upgrade that changes the default still reaches a reader
  /// who never touched this setting.
  String _model = '';

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

  /// Which engine is narrating the article currently open. See [Narrator].
  ///
  /// [Narrator.unknown] until [narrate] has run, and it runs once per article —
  /// so a play that starts before any article was named speaks with the device
  /// engine, which is the only engine that needs no probe.
  Narrator _narrator = Narrator.unknown;

  /// The platform's name for the voice [_pickDeviceVoice] chose. Reported so
  /// the Listen screen can name it rather than saying "the phone's voice".
  String _deviceVoiceName = '';

  /// A voice choice is in flight. Two callers can race here (a recorded
  /// narrator's fallback and the first sentence), and both doing `getVoices`
  /// and `setVoice` is harmless but wasteful; the flag keeps it to one.
  bool _choosingVoice = false;

  bool _sessionReady = false;

  @override
  bool get isPlaying => _current != null;

  /// What is speaking, not what was asked for. The two differ exactly when a
  /// recording failed, and that is the moment the reader most needs the truth.
  @override
  VoiceSource get source => _lastSpoken;

  @override
  bool get hasRecordedAudio => _configured == VoiceSource.recorded;

  @override
  DeviceVoice get deviceVoice => _device;

  /// The MiMo voice id in use for the article now narrating. What the API was
  /// actually sent, which is [_voice] resolved out of `Random`.
  @override
  String get speakingAs => _speakingAs;

  /// Which engine is narrating the article now open. See [Narrator].
  @override
  Narrator get narrator => _narrator;

  /// Point the player at an engine. Called at boot and whenever Settings
  /// changes, so neither screen has to know how the other one was configured.
  ///
  /// DELIBERATELY DOES NOT TOUCH [_speakingAs] WHILE AN ARTICLE IS NARRATING.
  ///
  /// It used to re-derive the voice from an empty article id, which rolled a
  /// DIFFERENT MiMo voice for the rest of the article the moment the reader
  /// opened Settings — a voice change in the middle of a piece, from a screen
  /// that has nothing to do with playback. The comment claimed "the next
  /// `narrate` will resolve properly", and nothing re-ran `narrate` after a
  /// settings change, so it never did.
  ///
  /// A change of engine or voice takes effect on the NEXT article, which is the
  /// only boundary a listener can hear it at.
  void configure({
    required VoiceSource source,
    String apiKey = '',
    String baseUrl = '',
    String voice = '',
    String model = '',
  }) {
    _configured = source;
    // Optimistic until proven otherwise: the label should name the engine the
    // reader asked for until one actually fails to answer.
    _lastSpoken = source;
    _apiKey = apiKey.trim();
    _model = model.trim();
    if (baseUrl.trim().isNotEmpty) _baseUrl = baseUrl.trim();
    if (voice.trim().isNotEmpty) {
      _voice = voice.trim();
      if (_narrator == Narrator.unknown) {
        // Nothing is playing, so this roll is the one the next article starts
        // from. `articleId` is '' because no article is being narrated yet.
        _speakingAs = _resolveVoice(_voice, '');
      }
    }
    // Whatever the new setting is, the article in flight keeps its narrator.
    // `narrate` re-decides at the next article boundary.
    if (_narrator != Narrator.unknown) return;
    _narrator = Narrator.unknown;
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

  /// Start narrating [articleId]. The ONE place the Random choice is applied,
  /// and the ONE place the engine is chosen.
  ///
  /// Called when an article opens, which is the boundary the choice belongs
  /// on: one article, one narrator, one engine. Resolving inside [stop] looked
  /// equivalent and was not — [play] stops the previous sentence on every call,
  /// so the narrator was re-resolved sentence by sentence and the piece became
  /// unlistenable.
  ///
  /// The engine is probed ONCE here rather than per sentence. That is the fix
  /// for the article that was half male and half female: a remote recording
  /// that failed used to drop that ONE sentence to the phone's default engine,
  /// so a piece could change narrator halfway through with nothing on screen
  /// saying so. Now a probe that fails means this whole article is spoken by
  /// the device, which is a consistent article rather than a patchwork.
  ///
  /// The same article always resolves to the same voice, so a sentence tapped
  /// on the Read screen, the Listen screen and a second listen next week all
  /// agree on who is speaking.
  @override
  void narrate(String articleId) {
    _speakingAs = _resolveVoice(_voice, articleId);
    // A configured recording with no key is not a recording. Deciding here,
    /// once, means `play` never has to ask again mid-article.
    if (_configured != VoiceSource.recorded || _apiKey.isEmpty) {
      _narrator = Narrator.device;
      return;
    }
    _narrator = Narrator.recorded;
    // The device voice is chosen up front, so a later fallback — a recording
    // that will not play — lands on a voice that was picked rather than on
    // whatever the platform happens to default to.
    unawaited(_ensureDeviceVoice());
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
    // DO NOT call `_ensureDeviceVoice` from here. That method awaits
    // `_ttsReady` (this very future) before touching the engine, so calling it
    // from inside the configuration deadlocked: `_ttsReady` waited for
    // `_ensureDeviceVoice`, and `_ensureDeviceVoice` waited for `_ttsReady`.
    // Nothing that awaited TTS ever resumed — `Say it` and the Listen player
    // both sat there silently. The voice is chosen on the first real speak
    // (`_speak` / `speakWord`), which is still before the first word.
  }

  /// Pick the voice the phone will speak with, and set it.
  ///
  /// WHY THIS EXISTS. `flutter_tts` was never told which voice to use, so it
  /// spoke with whatever the platform defaults to — typically female on both
  /// Android and iOS. That is invisible while the device engine is the only
  /// engine, and it is the other half of the half-male-half-female article the
  /// moment a recording falls back to it.
  ///
  /// The pick follows [_voice]: a male MiMo voice gets a male device voice, a
  /// female one a female, so a fallback is a change of timbre rather than a
  /// change of person. The match is by NAME rather than by any gender metadata,
  /// because `flutter_tts` exposes neither a gender nor a stable id — only the
  /// locale and whatever the engine chose to call the voice. So the names are
  /// matched heuristically and the result is REPORTED on the Listen screen
  /// instead of assumed: a reader who hears the wrong one can see which voice
  /// was picked and change it.
  ///
  /// Idempotent, and cheap after the first call: the answer is remembered.
  Future<void> _ensureDeviceVoice() async {
    if (_deviceVoiceName.isNotEmpty || _choosingVoice) return;
    _choosingVoice = true;
    try {
      await _ttsReady;
      final Object? raw = await _tts.getVoices;
      if (raw is! List) return;
      final List<Map<Object?, Object?>> voices = <Map<Object?, Object?>>[
        for (final Object? v in raw)
          if (v is Map) v,
      ];
      final Map<Object?, Object?>? pick = _pickDeviceVoice(voices);
      if (pick == null) return;
      // `setVoice` takes `Map<String, String>` while `getVoices` hands back
      // whatever the platform channel produced. The conversion is lossy by
      // design: a voice is identified by its name and its locale, and nothing
      // else in the map is load-bearing.
      await _tts.setVoice(<String, String>{
        for (final MapEntry<Object?, Object?> e in pick.entries)
          '${e.key}': '${e.value}',
      });
      _deviceVoiceName = '${pick['name'] ?? ''}'.trim();
      _device = DeviceVoice(
        available: true,
        note: 'English is installed',
        name: _deviceVoiceName,
      );
    } catch (e) {
      // A phone that will not list its voices still speaks. The label falls
      // back to the generic sentence, which is better than a dead player.
      debugPrint('the device voice could not be chosen: $e');
    } finally {
      _choosingVoice = false;
    }
  }

  /// Which of [voices] to use, or null when there is nothing en-US to choose.
  ///
  /// [wantedMale] comes from [_voice]: `Milo` and `Dean` are the male MiMo
  /// voices and everything else is female or neutral. The match is on the
  /// voice's own name, which on most engines carries it — `en-us-x-tpc#male`,
  /// `Male English (US)`, `Alex`. Where nothing matches, the FIRST en-US voice
  /// is taken rather than the platform default, because at least it is one this
  /// app chose and can name.
  Map<Object?, Object?>? _pickDeviceVoice(
    List<Map<Object?, Object?>> voices,
  ) {
    final List<Map<Object?, Object?>> english = <Map<Object?, Object?>>[
      for (final Map<Object?, Object?> v in voices)
        if ('${v['locale'] ?? ''}'.toLowerCase().startsWith('en-us')) v,
    ];
    if (english.isEmpty) return null;
    final bool wantedMale = _isMaleMiMoVoice(_voice);
    for (final Map<Object?, Object?> v in english) {
      final String name = '${v['name'] ?? ''}'.toLowerCase();
      final bool male = name.contains('male') && !name.contains('female');
      if (male == wantedMale) return v;
    }
    return english.first;
  }

  /// Whether a MiMo voice id is one of the male ones.
  ///
  /// A literal list rather than an inference: the ids are the five the API
  /// answers to, they are fixed, and a name-based guess would be a guess about
  /// a voice this app cannot hear.
  static bool _isMaleMiMoVoice(String voice) =>
      voice == 'Milo' || voice == 'Dean';

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
        _device = DeviceVoice(
          available: true,
          note: 'English is installed',
          // Whatever was chosen already, if a voice has been chosen. An empty
          // name here means `_ensureDeviceVoice` has not run yet, and the
          // Settings screen says the generic sentence rather than inventing one.
          name: _deviceVoiceName,
        );
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
    final String text = word.trim();
    if (text.isEmpty) return false;
    await stop();
    try {
      // The same prerequisites as a sentence: an audio session, a completed
      // configuration, and a CHOSEN voice. Without the voice this spoke with
      // the platform default while the Listen screen used the selected one —
      // two different speakers for the same word.
      await _ensureSession();
      await _ttsReady;
      await _ensureDeviceVoice();
      await _tts.setSpeechRate(rate);
      final Object? result = await _tts.speak(text);
      // flutter_tts answers 1 on success and 0/false when the engine refused
      // (no voice pack, speech service disabled). Returning true regardless was
      // why the reader saw no sound and no explanation.
      return result != 0 && result != false;
    } catch (e) {
      debugPrint('speakWord failed: $e');
      return false;
    } finally {
      try {
        await _tts.setSpeechRate(0.44);
      } catch (_) {
        // Restoring the article rate is best effort; a failed restore must not
        // turn a spoken word into a reported failure.
      }
    }
  }

  /// Prove a recorded voice works. Returns null on success, or a sentence the
  /// Settings screen can show verbatim.
  Future<String?> probeMiMo() async {
    try {
      await _api.testVoice(
          baseUrl: _baseUrl,
          apiKey: _apiKey,
          voice: _speakingAs,
          model: _model);
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

    // A recorded voice, when THIS ARTICLE is being narrated by one. The engine
    // was decided in [narrate] and is not re-asked per sentence: a recording
    // that fails here falls through to the device engine, and the device engine
    // has a voice that was CHOSEN to match — so a fallback is a change of
    // timbre within one narrator rather than a different person halfway through
    // the piece, which is the bug this whole arrangement exists to prevent.
    if (_narrator == Narrator.recorded && _apiKey.isNotEmpty) {
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
      // The voice is set here as well as in `_ensureDeviceVoice`, because the
      // engine can be reconfigured underneath us and a sentence spoken with the
      // platform default is exactly the bug being fixed.
      await _ensureDeviceVoice();
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
  /// the model, the voice AND the exact words, and a hit never touches the
  /// network at all. The model is part of the key because changing it can
  /// change the audio; without it, a reader who switched TTS models would keep
  /// hearing the old one from disk.
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
        model: _model,
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
      final ({Completer<void> gate, bool urgent}) next =
          _synthWaiters.removeAt(0);
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
    //
    // Reads [_narrator], not [_configured]: the question is which engine is
    // narrating THIS article, and a reader who turned the recording off after
    // this one started must not have the app synthesise sentences nobody will
    // hear.
    if (_narrator != Narrator.recorded || _apiKey.isEmpty) return;
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
    // An empty model is the provider default, and stays out of the key so
    // recordings made before this setting existed are still cache hits. A
    // custom model prefixes the key, which invalidates only its own audio.
    final String model = _model.trim();
    final String prefix = model.isEmpty ? '' : '$model|';
    return File(p.join(dir.path, '${_hash('$prefix$_speakingAs|$text')}.wav'));
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
            s == ja.ProcessingState.completed || s == ja.ProcessingState.idle,
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
    if (_narrator == Narrator.recorded && _apiKey.isNotEmpty) {
      final String? path = await _cachedRecording(_currentText, urgent: true);
      if (path != null && await _playFile(path)) {
        _lastSpoken = VoiceSource.recorded;
        return;
      }
    }
    try {
      await _ttsReady;
      await _ensureDeviceVoice();
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
