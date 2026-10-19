// Marginalia — three articles are always waiting.
//
// No-Stop English: an offline-first READER. Five screens, two verbs, and
// a queue of three. No schedule, no streak, and nothing anywhere asks whether you
// remember a word.
//
// "Offline-first" describes the reading half and nothing else. There is no local
// language model in this app — every article is written by a remote API over
// HTTPS, which is why a write needs a key and a connection and is the only thing
// here that costs money. Reading, listening and looking words up are local and
// free: bundled samples, a bundled 392,695-entry dictionary, SQLite, and the
// phone's own TTS engine.
//
// This file is the wiring: the domain rules live in lib/domain and import
// nothing, the storage in lib/data, and the screens in lib/features. What is here
// is only the state and the two writes that must never touch anything else —
// counting a read, and counting a listen.

import 'dart:async';
import 'dart:math' show Random;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart'
    show SystemChrome, SystemNavigator, SystemUiOverlayStyle;

import 'app/bottom_bar.dart';
import 'core/design/tokens.dart';
import 'core/util/motion.dart';
import 'core/widgets/primitives.dart';
import 'core/widgets/texture.dart';
import 'data/audio.dart';
import 'data/database.dart' hide WordRow;
import 'data/dictionary.dart';
import 'data/handler.dart';
import 'data/keystore.dart';
import 'data/remote/agent.dart';
import 'data/remote/api.dart';
import 'data/remote/log.dart';
import 'data/remote/mcp.dart';
import 'data/remote/news.dart';
import 'data/remote/tools.dart';
import 'data/repository.dart';
import 'data/samples.dart';
import 'data/writer.dart';
import 'domain/instruction.dart';
import 'domain/library.dart';
import 'domain/models.dart';
import 'domain/picture.dart';
import 'domain/plan.dart';
import 'domain/queue.dart';
import 'domain/sequence.dart';
import 'domain/stopwords.dart';
import 'domain/subjects.dart';
import 'domain/word_pool.dart';
import 'features/article/article_screen.dart';
import 'features/article/listen_screen.dart';
import 'features/article/word_sheet.dart';
import 'features/history/history_screen.dart';
import 'features/library/library_screen.dart';
import 'features/queue/picture_sheet.dart';
import 'features/queue/queue_card.dart';
import 'features/queue/regenerate_sheet.dart';
import 'features/settings/debug_log_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/words/words_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The icons start light because the app's default surface is `warm paper` —
  // a light surface, which needs DARK icons. The old value was hard-coded the
  // other way round (written for the dark palette), so on the default surface
  // the clock and the battery were drawn in near-white on cream. `_applyChrome`
  // below is what keeps them right once the reader picks a surface.
  _applyChrome(Palette.warmPaper);

  // The lock-screen transport, started before the first frame because
  // `AudioService.init` is what registers the foreground service — and a service
  // registered late is a sentence that stops the moment the screen goes dark.
  //
  // A failure here is not fatal and must not be. The Listen tab works perfectly
  // in the foreground; an app that refused to open because a notification could
  // not be arranged would be a worse app than one that plays without one.
  MarginaliaAudioHandler? handler;
  try {
    handler = await AudioService.init(
      builder: MarginaliaAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.marginalia.reader.listening',
        androidNotificationChannelName: 'Listening',
        // Ongoing while playing, so Android does not treat the notification as
        // dismissible and take the foreground service down with it.
        androidNotificationOngoing: true,
        // Paused means paused: leave the foreground rather than hold the phone
        // awake for a sentence nobody is hearing.
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e) {
    debugPrint('lock-screen transport unavailable: $e');
  }

  runApp(MarginaliaApp(audioHandler: handler));
}

/// Point the status-bar icons at the surface they sit on.
///
/// Both values are needed and they are NOT the same thing:
/// `statusBarIconBrightness` is for Android's own icons, `statusBarBrightness`
/// is what iOS reads to decide the same question. A light surface wants dark
/// icons; a dark surface wants light ones.
void _applyChrome(Palette p) {
  final bool dark = p.brightness == Brightness.dark;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: p.paper,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
    ),
  );
}

class MarginaliaApp extends StatefulWidget {
  const MarginaliaApp({super.key, this.audioHandler});

  /// Handed straight down to the Listen screen, which is the only thing in the
  /// app that plays a whole article.
  final MarginaliaAudioHandler? audioHandler;

  @override
  State<MarginaliaApp> createState() => _MarginaliaAppState();
}

class _MarginaliaAppState extends State<MarginaliaApp>
    with WidgetsBindingObserver {
  /// Which surface to show, and the phone's own opinion about it.
  ///
  /// [AppearanceMode.system] needs BOTH of these and the observer below.
  /// `MediaQuery.platformBrightnessOf` is not available here: this widget is
  /// ABOVE `MaterialApp`, so there is no MediaQuery to read. The binding's own
  /// `platformBrightness` is the value, and `didChangePlatformBrightness` is
  /// the only notification that it moved.
  AppearanceMode _appearance = AppearanceMode.system;
  Brightness _platform = Brightness.light;

  /// The face articles are set in. Not a palette concern, but it is persisted
  /// the same way and it has to reach the whole tree, so it is held here.
  ReadingFace _face = ReadingFace.notoSerif;

  Palette get _palette => _appearance.paletteFor(_platform);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _platform = WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (!mounted) return;
    // setState even when the mode is fixed, because the stored value is what a
    // later switch back to `system` resolves against — and because rebuilding
    // on a brightness change that does not matter costs one frame.
    setState(() => _platform = WidgetsBinding.instance.platformDispatcher.platformBrightness);
  }

  void _setAppearance(AppearanceMode mode) {
    setState(() => _appearance = mode);
    _applyChrome(_appearance.paletteFor(_platform));
    _onPreference?.call('ui:appearance', mode.name);
  }

  void _setFace(ReadingFace face) {
    setState(() => _face = face);
    _onPreference?.call('ui:readingFace', face.name);
  }

  /// How the app writes a preference down. Set by `_Shell` once the database is
  /// open, because the database is opened there — the app root has no storage
  /// of its own, and inventing a second one to save one string would be a
  /// second place for the same setting to live.
  void Function(String key, String value)? _onPreference;

  /// Called by `_Shell` when the stored preferences come back.
  void _adoptPreferences(AppearanceMode appearance, ReadingFace face) {
    if (!mounted) return;
    setState(() {
      _appearance = appearance;
      _face = face;
      _platform = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    });
    _applyChrome(_palette);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Marginalia',
      debugShowCheckedModeBanner: false,
      theme: MarginaliaTheme.themeFor(_palette),
      builder: (BuildContext context, Widget? child) =>
          ReadingFaceScope(face: _face, child: child ?? const SizedBox()),
      home: _Shell(
        palette: _palette,
        audioHandler: widget.audioHandler,
        appearance: _appearance,
        face: _face,
        onAppearance: _setAppearance,
        onFace: _setFace,
        onReady: (void Function(String, String) save,
            AppearanceMode a, ReadingFace f) {
          _onPreference = save;
          _adoptPreferences(a, f);
        },
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell({
    required this.palette,
    required this.appearance,
    required this.face,
    required this.onAppearance,
    required this.onFace,
    required this.onReady,
    this.audioHandler,
  });

  final Palette palette;
  final AppearanceMode appearance;
  final ReadingFace face;
  final ValueChanged<AppearanceMode> onAppearance;
  final ValueChanged<ReadingFace> onFace;

  /// Hands the app root its save function and the stored preferences, once the
  /// database is open. See `_MarginaliaAppState._onPreference`.
  final void Function(
    void Function(String key, String value) save,
    AppearanceMode appearance,
    ReadingFace face,
  ) onReady;

  final MarginaliaAudioHandler? audioHandler;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with WidgetsBindingObserver {
  final AppDatabase _db = AppDatabase();
  late final LibraryRepository _repo = LibraryRepository(_db);
  final SentenceAudio _audio = SentenceAudio();
  final KeyStore _keys = const KeyStore();
  final RemoteApi _api = RemoteApi();
  late final ArticleWriter _writer = ArticleWriter(_api);

  Dictionary? _dict;

  /// One shared load: concurrent taps must not each start a 39 MB parse.
  Future<Dictionary?>? _dictFuture;

  /// Set when boot could not finish, so the screen can say so out loud.
  String? _bootError;
  WordPool? _pool;

  /// The bundled articles, by id. The queue holds identities; the body is
  /// resolved here so no article text is duplicated into the database.
  final Map<String, SampleArticle> _samples = <String, SampleArticle>{};
  Queue? _queue;
  ReadingPlan _plan = const ReadingPlan();

  Dest _tab = Dest.queue;

  /// Pushed screens, so Back returns rather than jumping to the root. A bare
  /// switchboard would drop the reading position; a full router is more than four
  /// destinations need right now.
  ///
  /// These are BUILDERS, not built widgets, and that is not a style choice.
  /// Holding a constructed widget meant `build()` returned the same instance on
  /// every rebuild, so Flutter's `canUpdate` saw an identical widget and skipped
  /// the subtree entirely: the Settings panes were built once and never again.
  /// Saving a key wrote it to the keystore, rebuilt the shell, and the pane went
  /// on showing "not set" — which is exactly why MiMo looked impossible to
  /// configure. A builder is rebuilt on every frame the shell rebuilds, so what
  /// is on screen always comes from the state that is actually current.
  final List<Widget Function()> _stack = <Widget Function()>[];

  int _planCounter = 0;

  /// Draws the concrete subject a free plan shows BEFORE it is written.
  ///
  /// Without this, a planned card says `Anything` and `Change it` opens onto a
  /// blank decision: the reader cannot tell two plans apart, so changing one is
  /// meaningless. The draw is local and free, and the card carries the sentence
  /// all the way to the writer.
  final SubjectSuggester _suggester = SubjectSuggester();

  /// Today's Zhihu Daily headlines, when the reader configured that source.
  ///
  /// Fetched once per launch (unawaited, free, and optional) and used as the
  /// PREFERRED pool for plan previews. A headline is fresher than any fixed
  /// list, and the source is already integrated for writing — this just lets the
  /// card show one of its subjects before any money is spent. Empty means the
  /// built-in catalogue is used: no key, the source switched off, offline, or
  /// the request has not finished yet.
  List<String> _subjectSeeds = const <String>[];
  bool _booted = false;
  bool _noticeShown = false;
  String? _openId;
  bool _openFromLibrary = false;

  /// The sentence being spoken from the reading screen, or -1. Lives here so the
  /// article screen can mark the line without owning the audio.
  int _speakingIndex = -1;

  // ── reader preferences, persisted in the settings table ────────────────
  ReadSize _readSize = ReadSize.medium;
  ListenSize _listenSize = ListenSize.large;

  /// Whether opening the Listen screen starts speaking. Off by default: some
  /// readers want it, others are in a quiet room and a screen that talks first
  /// is a scare, not a feature.
  bool _listenAutoPlay = false;

  /// What happens when one article plays to its last sentence.
  /// `off` — stop. `forever` — keep going. `count` — keep going [n] more times.
  String _listenAutoContinue = 'off';
  int _listenAutoContinueCount = 3;

  /// How the next article is picked when auto-continue fires.
  ///
  /// `onward` (the default) steps toward what has waited longest, `backward`
  /// toward what arrived last. Both WRAP, so a run does not stop at the end of
  /// the ring. The other three are re-asked each time rather than stepped, so
  /// they can repeat an article before the run has been all the way round.
  ListenOrder _listenOrder = ListenOrder.onward;

  /// The stored name of [_listenOrder]. Kept in step with it, because the
  /// preference is a string on disk and the order is an enum in memory.
  String get _listenAutoOrder => _listenOrder.key;

  /// Whether the app writes the next article by itself.
  ///
  /// ON BY DEFAULT, and that is the whole feature: a reader who has to tap
  /// `Write it` after every article is a reader maintaining a queue, which is the
  /// chore this app exists to remove. Turning it off restores the old behaviour
  /// exactly — the queue still holds three cards, the reader just writes them
  /// themselves.
  ///
  /// It is a preference and not a lock. Every card still has its `Write it`, its
  /// `↻`, its `▣` and its `Change it`, and all of them work the same whether
  /// this is on or off. Automatic writing only fills the gap the reader left.
  bool _autoWrite = true;

  /// How many articles the app has written by itself this month. Zero until the
  /// counter is read, and the row says "nothing yet" rather than showing a stale
  /// number from last month.
  int _autoWriteUsed = 0;

  /// Read the counter. Called at boot and whenever Settings is opened, so the
  /// Settings row is a fact and not a memory.
  ///
  /// It used to run at boot only, so an app left open across the 1st kept
  /// showing last month's "58 of 60" while the gate itself had already allowed a
  /// fresh 60 — the number then jumped to "1 of 60" on the next write with no
  /// explanation. Reading it on the way into Settings costs one query and means
  /// the row can never disagree with the thing it is describing.
  Future<void> _loadAutoWriteUsed() async {
    try {
      final String? month = await _repo.setting(_autoMonthKey);
      if (month != _autoMonth()) {
        // A new month. The counter starts again, and so does the one-shot
        // ceiling notice — otherwise a reader who filled March would never be
        // told about April.
        if (month != null) await _save(_autoFullKey, '');
        if (!mounted) return;
        setState(() => _autoWriteUsed = 0);
        return;
      }
      final int used = int.tryParse(await _repo.setting(_autoCountKey) ?? '') ?? 0;
      if (!mounted) return;
      setState(() => _autoWriteUsed = used);
    } catch (e) {
      debugPrint('the automatic-write counter could not be read: $e');
    }
  }

  /// Mirrors of the two preferences the app root owns. Held here too because
  /// this is where the Settings screen is built from, and because this is the
  /// object that can reach the database to save them.
  AppearanceMode _appearance = AppearanceMode.system;
  ReadingFace _face = ReadingFace.notoSerif;

  // ── the two keys and where they point ─────────────────────────────────
  String _writerId = 'deepseek';
  String _writerBase = WriterEndpoint.deepseek.baseUrl;

  /// The model id sent to the writer. Empty means "whatever the provider
  /// default is" — which is what makes a provider's new model usable without a
  /// new APK: the reader types the id in Settings and the next write uses it.
  String _writerModel = '';

  String _voiceBase = VoiceEndpoint.mimo.baseUrl;
  String _voiceName = VoiceEndpoint.mimo.voices.first;

  /// The TTS model id. Empty means the provider default, for the same reason.
  String _voiceModel = '';
  String _voiceSourceId = 'device';

  /// The endpoint actually used for a request: the chosen provider, with the
  /// reader's own base URL and model laid over it.
  ///
  /// This is the fix for two latent lies. The writer Base URL was editable,
  /// saved and displayed — and never used, because every call site went through
  /// `WriterEndpoint.byId` and its const `baseUrl`. The model had no setting at
  /// all. Both now travel together through one getter so no call site can pick
  /// up one of them and forget the other.
  WriterEndpoint get _writerEndpoint {
    final WriterEndpoint base = WriterEndpoint.byId(_writerId);
    final String url = _writerBase.trim();
    final String model = _writerModel.trim();
    return base.copyWith(
      baseUrl: url.isEmpty ? null : url,
      model: model.isEmpty ? null : model,
    );
  }

  @override
  void initState() {
    super.initState();
    // The shell observes the lifecycle because THIS is where the queue lives.
    // The app root above also observes, but it owns the theme and nothing else —
    // and a lifecycle callback that has to reach down into the shell to find the
    // queue is the side channel this project keeps refusing to build.
    WidgetsBinding.instance.addObserver(this);
    _boot();
    // Deliberately NOT awaited and not part of `_boot`. Reading the version
    // touches the platform channel, and the boot sequence is ordered on purpose
    // — a version string is not worth a place in it. It lands whenever it lands
    // and the hub row fills itself in.
    unawaited(_loadVersion());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _db.close();
    _audio.dispose();
    _api.close();
    super.dispose();
  }

  /// The reader came back to the app. One of the three moments an article may be
  /// written by itself.
  ///
  /// FOREGROUND ONLY, AND THAT IS THE DESIGN. The obvious way to build "the next
  /// one is written automatically" is a background task on a timer, and it is the
  /// one thing this app refuses to do: a task that runs at 3am while the phone
  /// charges spends money with nobody watching, which is precisely the surprise
  /// the cost ceiling was written to make impossible. A reader who finished
  /// yesterday's third article and went to bed gets the next one when they open
  /// the app — not at 3am, and not before they are looking at the screen.
  ///
  /// `inactive` and `hidden` are ignored on purpose. `inactive` fires when a
  /// notification shade is pulled down and when the app-switcher appears, which
  /// is not the reader coming back; `hidden` is the screen going off.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_booted || _bootError != null) return;
    // Headlines age; refresh the preview pool when the reader comes back.
    unawaited(_refreshSubjectSeeds());
    // Same repair pass as boot: a queue that finished while the app was being
    // killed, or a card whose two counts landed a moment apart, is cleaned the
    // next time the reader comes back.
    unawaited(_reconcileQueue());
  }

  Future<void> _boot() async {
    await ensureSqliteReady();

    // Startup runs in order, not in parallel.
    //
    // Inflating 39 MB of dictionary while drift is creating its schema is what
    // produced BOTH first-run failures at the same instant:
    //     SqliteException(5): database is locked
    //     PathNotFoundException: Cannot rename .../dictionary.json
    // Doing the two at once put file and database work in the same directory on
    // the same IO path. The database goes first because it is small and the
    // reader wants it; the dictionary follows immediately after, and the UI
    // appears as soon as the queue is loaded rather than waiting on 39 MB of
    // json.
    // Every step reports itself. A boot that fails silently leaves the reader
    // staring at a wordmark forever with no idea why.
    Queue q;
    try {
      debugPrint('boot: opening the queue');
      q = await _repo.loadQueue(planFactory: _freePlan);
      debugPrint('boot: queue has ${q.length} slots');
    } catch (e, st) {
      debugPrint('boot: the queue could not be read: $e');
      debugPrint('boot: $st');
      if (mounted) {
        setState(() {
          _bootError = '$e';
          _booted = true;   // otherwise the message is set but never seen
        });
      }
      return;
    }

    ReadingPlan savedPlan;
    try {
      debugPrint('boot: reading the reading plan');
      savedPlan = await _repo.loadPlan();
    } catch (e) {
      debugPrint('boot: plan unavailable: $e');
      savedPlan = const ReadingPlan();
    }

    WordPool pool;
    try {
      debugPrint('boot: reading the word pool');
      pool = await _repo.loadWords();
    } catch (e, st) {
      debugPrint('boot: the word pool could not be read: $e');
      debugPrint('boot: $st');
      // Not fatal: the reader can still read, just without a pool.
      pool = WordPool(const <WordEntry>[]);
    }

    List<SampleArticle> samples;
    try {
      debugPrint('boot: reading the bundled samples');
      samples = await loadSamples();
    } catch (e, st) {
      debugPrint('boot: samples unavailable: $e');
      debugPrint('boot: $st');
      samples = const <SampleArticle>[];
    }

    // Preferences and keys. Read BEFORE the first frame so the notice and the
    // settings hub state what is actually configured rather than a guess.
    await _loadPreferences();
    // Free, optional, and off the critical path: today's headlines give plan
    // previews a fresher pool than the built-in catalogue.
    unawaited(_refreshSubjectSeeds());

    if (!mounted) return;
    debugPrint('boot: samples are ${samples.length}, showing the queue');

    setState(() {
      _samples.clear();
      for (final SampleArticle a in samples) {
        _samples[a.id] = a;
      }
      _queue = q;
      _pool = pool;
      _plan = savedPlan;
    });

    await _installSamples(samples);

    // The queue cards carry their read and listen counts, so those have to be
    // on screen with the cards rather than arriving a frame later — a card that
    // renders without its counter and then grows one is a card that looks broken
    // for a moment.
    await _loadQueueCounts();
    await _loadAutoWriteUsed();

    // Ask the phone what it can speak with, so the voice pane can state a fact
    // instead of leaving the reader to discover it by pressing play.
    unawaited(_audio.probeDevice());
    unawaited(_dictionaryOnce());

    // THIS is what ends the splash.
    debugPrint('boot: done');
    if (mounted) setState(() => _booted = true);

    // The notice comes AFTER the queue is on screen, never in front of it. It is
    // an offer, not a gate.
    unawaited(_maybeShowSetupNotice());

    // RECONCILE — and this is the line that fixes the queue a reader sees
    // after upgrading. "Finished" used to mean "read once OR heard once", and
    // older builds therefore left articles in the queue whose counts were
    // already complete under the current rule. The live path retires them as
    // they finish, but nothing ever cleaned a queue that was already full of
    // them. This does: every card whose read and listen are both non-zero
    // leaves now, and a new one is written if the queue has nothing untouched.
    //
    // It also covers the cold-launch write: a queue left with a plan is filled
    // on opening, not only after the reader finishes something else.
    unawaited(_reconcileQueue());
  }

  /// Preferences live in the settings table because they are not secrets: a
  /// reading size and a base URL are ordinary data. KEYS do not — they are in the
  /// keystore, and nothing else may read them.
  Future<void> _loadPreferences() async {
    Future<String?> get(String k) async {
      try {
        return await _repo.setting(k);
      } catch (e) {
        debugPrint('preference $k unavailable: $e');
        return null;
      }
    }

    final String? size = await get('ui:readSize');
    final String? lsize = await get('ui:listenSize');
    final String? appearance = await get('ui:appearance');
    final String? face = await get('ui:readingFace');
    final String? wid = await get('writer:id');
    final String? wbase = await get('writer:base');
    final String? wmodel = await get('writer:model');
    final String? vbase = await get('voice:base');
    final String? vname = await get('voice:name');
    final String? vmodel = await get('voice:model');
    final String? vsrc = await get('voice:source');
    // Listen behaviour. Absent means OFF / no-continue / newest — the quiet
    // defaults, so a reader who has never opened Settings is never surprised.
    final String? lauto = await get('listen:autoPlay');
    final String? lcont = await get('listen:autoContinue');
    final String? lcontN = await get('listen:autoContinueCount');
    final String? lorder = await get('listen:autoOrder');
    // Absent means ON, and that is the one default in this file that is not the
    // quiet one. Every other preference here defaults to "do nothing until
    // asked"; this one defaults to "keep the queue full", because a queue that
    // empties unless somebody maintains it is the chore the app is for. A reader
    // who disagrees turns it off in Settings and it stays off.
    final String? autoWrite = await get('auto:write');
    // The two optional sources. Absent means ON — the reader saved a key, and
    // the common case is that they saved it because they wanted it. Only an
    // explicit "off" switches it off.
    final bool newsOnPref = (await get('news:on')) != 'off';
    final bool searchOnPref = (await get('search:on')) != 'off';

    final (bool hasWriter, bool hasVoice, bool hasNews, bool hasSearch) =
        await _keys.status();
    final String? voiceKey = await _keys.voice();
    // These two flags are what the Settings hub and its Test buttons read. They
    // were read from the keystore here and then dropped on the floor, so a
    // reader who had saved a key was still told they had not.

    final WriterEndpoint endpoint = WriterEndpoint.byId(wid ?? 'deepseek');

    if (!mounted) return;
    setState(() {
      _hasWriterKey = hasWriter;
      _hasVoiceKey = hasVoice;
      // Saving a key switches its source on; the switch in Settings can turn it
      // off again without the reader having to delete the key and paste it back.
      // So a saved key is the DEFAULT for the switch, not the switch itself.
      _hasNewsKey = hasNews;
      _hasSearchKey = hasSearch;
      _newsOn = hasNews && newsOnPref;
      _searchOn = hasSearch && searchOnPref;
      _readSize = ReadSize.values.firstWhere(
        (ReadSize r) => r.label == size,
        orElse: () => ReadSize.medium,
      );
      _listenSize = ListenSize.values.firstWhere(
        (ListenSize r) => r.label == lsize,
        orElse: () => ListenSize.large,
      );
      _listenAutoPlay = lauto == 'on';
      _listenAutoContinue = <String>{'off', 'forever', 'count', 'loop'}
              .contains(lcont)
          ? lcont!
          : 'off';
      _listenAutoContinueCount = int.tryParse(lcontN ?? '') ?? 3;
      if (_listenAutoContinueCount < 1) _listenAutoContinueCount = 1;
      // The stored name maps through the enum, which owns the legacy names.
      // `newest` was the old default and is not a direction — it meant "the
      // card that arrived most recently", which is now `backward`'s job — so a
      // reader who never touched this setting gets `onward`: the newest thing in
      // the queue is the thing they have not met, which is what a queue is for.
      _listenOrder = ListenOrder.fromKey(lorder);
      _writerId = endpoint.id;
      // The two appearance preferences are resolved here and handed UP to the
      // app root, which owns the theme. Stored by NAME rather than by index, so
      // inserting a face into the enum cannot silently move every reader to a
      // different font.
      _appearance = AppearanceMode.values.firstWhere(
        (AppearanceMode a) => a.name == appearance,
        orElse: () => AppearanceMode.system,
      );
      _face = ReadingFace.values.firstWhere(
        (ReadingFace f) => f.name == face,
        orElse: () => ReadingFace.notoSerif,
      );
      _writerBase = wbase ?? endpoint.baseUrl;
      _writerModel = wmodel ?? '';
      _voiceBase = vbase ?? VoiceEndpoint.mimo.baseUrl;
      _voiceName = vname ?? VoiceEndpoint.mimo.voices.first;
      _voiceModel = vmodel ?? '';
      _voiceSourceId = vsrc ?? (hasVoice ? 'mimo' : 'device');
      // Only an explicit 'off' switches it off. Absent is ON — see the note
      // where it is read.
      _autoWrite = autoWrite != 'off';

      // Selecting MiMo with no key would produce a player that silently falls
      // back to the device voice on every sentence. Selection is honoured only
      // when it can actually be honoured.
      if (_voiceSourceId == 'mimo' && !hasVoice) _voiceSourceId = 'device';

      _audio.configure(
        source: _voiceSourceId == 'mimo'
            ? VoiceSource.recorded
            : VoiceSource.device,
        apiKey: voiceKey ?? '',
        baseUrl: _voiceBase,
        voice: _voiceName,
        model: _voiceModel,
      );
    });

    // Hand the app root its save function and the two preferences it owns. It
    // is done HERE rather than in `initState` because this is the first moment
    // the database has answered: a root that saved a preference before then
    // would be writing to a repository that does not exist yet, and a root that
    // THEMED itself before then would flash the wrong surface on every launch.
    widget.onReady(_save, _appearance, _face);
  }

  Future<void> _save(String key, String value) async {
    try {
      await _repo.setSetting(key, value);
    } catch (e) {
      debugPrint('could not save $key: $e');
    }
  }

  /// Ask the writer for a new plan. The ONLY other paid call in the app, and
  /// like the first one it is reachable only from a tap.
  ///
  /// The plan's own diff/accept machinery lives in the sheet and in
  /// `PlanRewrite`; this method's whole job is the key, the endpoint and the
  /// translation of a missing key into a sentence. It does NOT catch
  /// `RemoteFailure` — the sheet does, because the sheet is what has somewhere
  /// to show it.
  Future<PlanRewrite> _rewritePlan(String request) async {
    final String? key = await _keys.writer();
    if (key == null || key.trim().isEmpty) {
      throw const RemoteFailure(
          'No key is saved, so nothing was sent. Add one under Who writes.');
    }
    return _writer.rewritePlan(
      plan: _plan,
      request: request,
      apiKey: key,
      endpoint: _writerEndpoint,
    );
  }

  /// Save the reading plan. Eight fields plus the reader's own words, and the
  /// toast says what saving a plan does NOT do: nothing is written until the
  /// card's Write it is tapped.
  Future<void> _savePlan(ReadingPlan p) async {
    setState(() => _plan = p);
    try {
      await _repo.savePlan(p);
    } catch (e) {
      debugPrint('the plan could not be saved: $e');
    }
  }

  /// Load the dictionary once. Concurrent taps share one load rather than each
  /// starting their own.
  Future<Dictionary?> _dictionaryOnce() {
    return _dictFuture ??= _loadDictionary().then((Dictionary? d) {
      if (d != null) _dict = d;
      return d;
    });
  }

  /// A failure here must not take the app down: the app is still readable
  /// without a dictionary, and a lookup that cannot answer says so plainly
  /// rather than showing nothing.
  Future<Dictionary?> _loadDictionary() async {
    try {
      return await Dictionary.load();
    } catch (e) {
      debugPrint('dictionary unavailable: $e');
      return null;
    }
  }

  /// Put the bundled articles into empty slots, once.
  ///
  /// This is the one path that makes a slot ready without a tap and without
  /// spending anything: the article already shipped on the phone, so nothing was
  /// generated. It runs on first launch only, and never over a slot that already
  /// holds something — a reader's own history is not replaceable by a sample.
  Future<void> _installSamples(List<SampleArticle> samples) async {
    if (samples.isEmpty) {
      debugPrint('boot: no samples in the bundle');
      return;
    }
    debugPrint('boot: installing ${samples.length} sample(s)');

    // The whole thing is guarded. A failure here must not strand the reader on
    // the wordmark: the queue already has three plans in it, so the app can open
    // perfectly well without a sample, it just has nothing to read yet.
    try {
      final List<int> empties = await _repo.emptySlotIndices();
      debugPrint('boot: ${empties.length} slot(s) free');

      int slot = 0;
      for (final SampleArticle a in samples) {
        if (await _repo.sampleInstalled(a.id)) continue;
        if (slot >= empties.length) break;
        debugPrint('boot: putting "${a.title}" into slot ${empties[slot]}');
        await _repo.installSample(
          index: empties[slot],
          articleId: a.id,
          title: a.title,
          keywords: a.keywords,
          kilobytes: a.kilobytes,
        );
        await _repo.markSampleInstalled(a.id);
        slot++;
      }
      debugPrint('boot: installed $slot sample(s)');

      if (slot > 0 && mounted) {
        _queue = await _repo.loadQueue(planFactory: _freePlan);
        debugPrint('boot: queue reloaded with ${_queue!.length} slots');
      }
    } catch (e, st) {
      // Not fatal. The reader gets three plans and a working app.
      debugPrint('boot: samples could not be installed: $e');
      debugPrint('boot: $st');
    }
  }

  /// A plan costs nothing: no call, no key, no time.
  ///
  /// The length is drawn at RANDOM from the three bands rather than fixed at
  /// medium. A queue of three identical lengths is a queue that stops
  /// surprising anyone, and variety is the one thing a reading app can offer
  /// for free. `_randomBand` excludes `custom`, which has no number of its own
  /// until a reader types one.
  ///
  /// The SUBJECT is drawn here too — locally, for free, from
  /// [kSuggestedSubjects]. That is what makes `Change it` mean anything: the
  /// card shows the exact sentence the writer will be given, so the reader can
  /// keep it, edit it, or replace it with one of their own. [avoid] carries
  /// whatever the caller knows must not be drawn again (the plan being
  /// replaced); the queue's other planned cards are excluded automatically.
  QueueSlot _freePlan({Iterable<String> avoid = const <String>[]}) {
    _planCounter++;
    final LengthBand band = _randomBand();
    final Set<String> blocked = <String>{
      ...avoid,
      for (final QueueSlot s in _queue?.slots ?? const <QueueSlot>[])
        if (s.isPlanned && s.instruction.trim().isNotEmpty) s.instruction,
    };
    final String subject =
        _suggester.next(avoid: blocked, preferred: _subjectSeeds);
    return QueueSlot(
      articleId: 'plan-${DateTime.now().millisecondsSinceEpoch}-$_planCounter',
      state: SlotState.planned,
      instruction: subject,
      instructionId: _subjectSeeds.contains(subject)
          ? kHeadlineInstructionId
          : kSuggestedInstructionId,
      plannedWords: _plan.wordsFor(band),
      plannedBand: band,
    );
  }

  /// Fetch today's headlines for plan previews.
  ///
  /// One request, free, and entirely optional. It does NOT write anything and
  /// does not call a model: it only gives `_freePlan` a fresher pool of subjects
  /// than the built-in catalogue. A failure leaves the catalogue in place, which
  /// is why this is unawaited and never reports an error.
  Future<void> _refreshSubjectSeeds() async {
    if (!_newsOn) return;
    try {
      final String? key = await _keys.news();
      if (key == null || key.trim().isEmpty) return;
      final NewsSource source = NewsSource();
      try {
        final List<NewsItem> items = await source.hotboard(apiKey: key);
        final List<String> titles = <String>[
          for (final NewsItem n in items)
            if (n.title.trim().isNotEmpty) n.title.trim(),
        ];
        if (!mounted || titles.isEmpty) return;
        setState(() => _subjectSeeds = titles);
      } finally {
        source.close();
      }
    } catch (e) {
      // No key, no network, endpoint moved: the catalogue still works.
      debugPrint('plan previews will use the built-in subjects: $e');
    }
  }

  /// One of the three bands, uniformly. Seeded from the clock, because a queue
  /// that rerolls to the same length twice is a reroll that looks broken.
  LengthBand _randomBand() {
    const List<LengthBand> bands = <LengthBand>[
      LengthBand.short,
      LengthBand.medium,
      LengthBand.long,
    ];
    return bands[Random().nextInt(bands.length)];
  }

  void _push(Widget Function() screen) => setState(() => _stack.add(screen));

  void _pop() {
    if (_stack.isEmpty) return;
    setState(() => _stack.removeLast());
  }

  /// The startup notice. Shown ONCE, and only when something is actually
  /// missing.
  ///
  /// It is not a gate: the app is fully usable with neither key, so the notice
  /// says exactly that and offers a button rather than demanding an answer. Two
  /// buttons, no third: `Set up now` and `Got it` — and the second one is the
  /// sheet frame's own Close under a truer name, not a second control beside it.
  Future<void> _maybeShowSetupNotice() async {
    // Only the first two matter here, and that is deliberate. The news and
    // search keys are enhancements, not setup: telling a reader their app is
    // "not configured" because they have not bought a search key would be a
    // notice about something they never asked for, and the second such notice
    // is the one they stop reading.
    final (bool hasWriter, bool hasVoice, _, _) = await _keys.status();
    if (!mounted || _noticeShown) return;
    if (hasWriter && hasVoice) return;

    // Once the reader has answered, they are not asked again on every launch.
    try {
      if (await _repo.setting('notice:setup') == 'seen') return;
    } catch (e) {
      debugPrint('notice flag unavailable: $e');
    }

    _noticeShown = true;
    await _save('notice:setup', 'seen');

    await AppSheet.show<void>(
      context,
      title: 'Two things are not set up',
      // The frame owns the one dismiss control; naming it here is what keeps
      // this sheet to two buttons instead of three. A body that added its own
      // "Got it" beside the frame's "Close" would be two controls for one
      // action — the exact thing this sheet was reported for.
      closeLabel: 'Got it',
      builder: (BuildContext ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(Gap.sheetPad, 0, Gap.sheetPad, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Neither is required. The app reads, writes nothing on its own, '
              'and speaks in the phone\'s own voice for free — offline, in '
              'airplane mode. What a key adds is a better voice and a cheaper '
              'writer.',
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 14,
                height: 1.65,
                color: ctx.colors.ink2,
              ),
            ),
            const SizedBox(height: 16),
            _noticeRow(
              ctx,
              'A writer key',
              hasWriter
                  ? 'saved — articles can be written when you tap Write it'
                  : 'not set — no article can be written yet',
              hasWriter,
            ),
            const SizedBox(height: 9),
            _noticeRow(
              ctx,
              'A voice key',
              hasVoice
                  ? 'saved — MiMo can read articles aloud'
                  : "not set — the phone's own voice is used, which is free",
              hasVoice,
            ),
            const SizedBox(height: 18),
            Btn(
              label: 'Set up now',
              onPressed: () {
                Navigator.of(ctx).pop();
                _push(_settings);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _noticeRow(
    BuildContext ctx,
    String title,
    String detail,
    bool done,
  ) {
    final Palette c = ctx.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          done ? Icons.check_circle_outline : Icons.circle_outlined,
          size: 16,
          color: done ? c.jade : c.ink3,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontFamily: TypeScale.sans,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(
                  fontFamily: TypeScale.serif,
                  fontSize: 13,
                  height: 1.5,
                  color: c.ink3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_booted) {
      // The queue is three plans or three articles and nothing else, so the
      // first frame can render immediately while the samples are read. What must
      // never happen is a blank screen, and a bare "…" for several seconds is a
      // blank screen with punctuation.
      return Scaffold(
        backgroundColor: context.colors.paper,
        body: SafeArea(
          child: PaperGrain(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'NO·STOP',
                    style: TextStyle(
                      fontFamily: TypeScale.mono,
                      fontSize: 10,
                      letterSpacing: 0.22,
                      color: context.colors.ink3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: 90,
                    child: HatchedBar(
                      fraction: 0,
                      color: context.colors.hair,
                      height: 3,
                    ),
                  ),
                  if (_bootError != null) ...<Widget>[
                    const SizedBox(height: 18),
                    SizedBox(
                      width: 280,
                      child: Text(
                        'Could not start.\n$_bootError',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: TypeScale.mono,
                          fontSize: 10,
                          color: context.colors.verm,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_bootError != null) {
      return _bootFailed(context, _bootError!);
    }

    // The system back button has to know about _stack. Without PopScope, Back
    // went straight out of the app from any screen, which is the one thing a
    // reader pressing Back expects never to happen.
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        // Let Flutter dismiss a sheet first: it owns its own route.
        final NavigatorState nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
          return;
        }
        if (_stack.isNotEmpty) {
          _pop();
          return;
        }
        if (_speakingIndex >= 0) {
          unawaited(_audio.stop());
          setState(() => _speakingIndex = -1);
          return;
        }
        if (_openId != null) {
          _leaveArticle();
          return;
        }
        if (_tab != Dest.queue) {
          setState(() => _tab = Dest.queue);
          return;
        }
        // Nothing left to go back to: leave.
        SystemNavigator.pop();
      },
      // ONE key decides what the transition is between: the tab, or the depth
      // of the pushed stack. Without a key AnimatedSwitcher sees an unrelated
      // widget on every shell rebuild and cross-fades the whole app whenever a
      // counter changes.
      child: AnimatedSwitcher(
        duration: motionDuration(context, Ease.fast),
        switchInCurve: Ease.outExpo,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (Widget child, Animation<double> animation) {
          if (reducedMotion(context)) return child;
          final Animation<Offset> slide = Tween<Offset>(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: KeyedSubtree(
          key: ValueKey<String>(_stack.isNotEmpty
              ? 'stack-${_stack.length}'
              : 'tab-${_tab.name}'),
          child: _stack.isNotEmpty ? _stack.last() : _root(),
        ),
      ),
    );
  }

  Widget _root() {
    final Queue q = _queue!;
    final int wanting = _pool?.crucial(todayDay()).length ?? 0;

    return PageScaffold(
      bottomBar: BottomBar(
        current: _tab,
        wordsWanting: wanting,
        onSelect: (Dest t) => setState(() {
          _tab = t;
          _stack.clear();
        }),
      ),
      child: switch (_tab) {
        Dest.queue => _queuePage(q),
        Dest.article => _articleTab(q),
        Dest.library => _libraryPage(q),
        Dest.history => _historyPage(),
        Dest.words => _wordsPage(),
      },
    );
  }

  // ── queue ─────────────────────────────────────────────────────────────

  /// Shown when the queue could not be read. It says what failed IN THE READER'S
  /// terms and gives one action, because a screen that only reports a failure is
  /// a dead end.
  Widget _bootFailed(BuildContext context, String message) {
    final Palette c = context.colors;
    return PageScaffold(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Could not start',
                style: TextStyle(
                  fontFamily: TypeScale.serif,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'The queue could not be opened. Nothing is lost — your articles '
                'and counts are still on this phone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: TypeScale.serif,
                  fontSize: 14,
                  height: 1.65,
                  color: c.ink2,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.paperSunk,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: c.hair),
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: TypeScale.mono,
                    fontSize: 10,
                    height: 1.5,
                    color: c.verm,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Btn(
                label: 'Try again',
                onPressed: () async {
                  setState(() {
                    _bootError = null;
                    _booted = false;
                  });
                  await _boot();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _queuePage(Queue q) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 6, Gap.gutter, 28),
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'NO·STOP',
              style: TextStyle(
                fontFamily: TypeScale.mono,
                fontSize: 10,
                letterSpacing: 0.22,
                color: context.colors.ink3,
              ),
            ),
            Material(
              color: context.colors.surface,
              shape: CircleBorder(
                  side: BorderSide(color: context.colors.hair)),
              child: InkWell(
                onTap: () => _push(_settings),
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(Icons.tune, size: 17, color: context.colors.ink2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Eyebrow('Queue · 3 waiting'),
        Text('Three waiting', style: context.texts.titleLarge),
        const SizedBox(height: 18),
        // The prototype's order: the cards, then the notice, then the aside.
        // The notice comes AFTER the list because it is a footnote about sound,
        // not an introduction to the queue.
        for (int i = 0; i < q.slots.length; i++)
          _revealCard(
            q.slots[i],
            QueueCard(
              slot: _hydrated(q.slots[i]),
              onOpen: () => _openArticle(q.slots[i]),
              onMenu: () => _slotMenu(context, q, i),
              onWrite: () => _write(q, i),
              onReroll: () => _reroll(q, i),
              // The camera, on the planned card only. See `_withPictures` for
              // why it is wired on the CARD and not in the ⋯ menu: this is a
              // two-second habit and a menu is not where two-second habits live.
              onPictures: q.slots[i].isPlanned && !q.slots[i].isWriting
                  ? () => _withPictures(q, i)
                  : null,
              // Read off the LIVE slot, not the hydrated copy. `_hydrated`
              // returns a value object for rendering; the flag that says a call
              // is in flight belongs to the slot the call is writing into.
              writing: q.slots[i].isWriting,
              // The card's price depends on whether a source is configured, so
              // the card is told rather than left to assume. A reader with no
              // optional keys still sees `Write it · ~$0.002`.
              research: _canResearch,
              // A bundled sample is not a generated article. Saying so on the
              // card is the difference between "the writer keeps producing the
              // same thing" and "this one shipped with the app".
              isSample: _samples.containsKey(q.slots[i].articleId),
              // What the reader has already done with it. Absent on a planned
              // card — there is nothing to have read yet.
              reads: _countOf(q.slots[i].articleId).reads,
              listens: _countOf(q.slots[i].articleId).listens,
            ),
          ),
        const SizedBox(height: 14),
        // A footnote, not a card. It used to wear the same surface and border
        // as an article card, so it read as a fourth tappable thing that never
        // responded. The one promise it makes is smaller than a card: it sits
        // under the queue the way any other aside does.
        const _Notice(),

      ],
    );
  }

  /// A card that arrives instead of appearing.
  ///
  /// The key is the slot's IDENTITY AND STATE — not the writing flag. A plan
  /// turning into an article changes the key, so the new card fades and rises;
  /// a counter or a "writing…" flag changing does not, so the card stays put
  /// while AnimatedSize absorbs the height difference. That distinction is what
  /// keeps the queue from flickering on every rebuild.
  Widget _revealCard(QueueSlot slot, Widget child) {
    final String identity =
        '${slot.articleId}-${slot.isPlanned ? 'plan' : 'ready'}';
    return AnimatedSize(
      duration: motionDuration(context, Ease.mid),
      curve: Ease.outExpo,
      alignment: Alignment.topCenter,
      child: TweenAnimationBuilder<double>(
        key: ValueKey<String>(identity),
        tween: Tween<double>(begin: 0, end: 1),
        duration: motionDuration(context, Ease.mid),
        curve: Ease.outExpo,
        builder: (BuildContext c, double t, Widget? inner) {
          if (inner == null || reducedMotion(c)) return inner ?? const SizedBox();
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - t)),
              child: inner,
            ),
          );
        },
        child: child,
      ),
    );
  }

  /// The card's ⋯ menu. Three real actions, matching the prototype's
  /// article menu: a different topic, write it again, done with it.
  Future<void> _slotMenu(BuildContext context, Queue q, int index) async {
    // Hydrated, to match the card: the raw stub has no body, so the menu would
    // call a written or bundled article 'the text is gone' while the card below
    // it still offered `Read`.
    final QueueSlot slot = _hydrated(q.slots[index]);
    final Palette c = context.colors;

    await AppSheet.show<void>(
      context,
      builder: (BuildContext ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(Gap.sheetPad, 0, Gap.sheetPad, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              slot.isPlanned ? slot.subjectLabel : 'What to do with it',
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              slot.isPlanned
                  ? 'not written yet'
                  : (slot.article?.sentences.isEmpty ?? true)
                      ? 'written, but the text is no longer on this phone'
                      : <String>[
                          '${slot.article?.wordCount ?? 0} words',
                          '≈ ${slot.article?.minuteEstimate ?? 0} min',
                          // What has been done with it, in the menu too. The
                          // card above carries the same line, and repeating it
                          // here is not redundancy: the reader opened this menu
                          // to decide what to DO, and the answer depends partly
                          // on how much they have already done it.
                          if (_countOf(slot.articleId).reads > 0)
                            'read ${times(_countOf(slot.articleId).reads)}',
                          if (_countOf(slot.articleId).listens > 0)
                            'heard ${times(_countOf(slot.articleId).listens)}',
                        ].join(' · '),
              style: TextStyle(
                fontFamily: TypeScale.mono,
                fontSize: 10.5,
                color: c.ink3,
              ),
            ),
            const SizedBox(height: 16),
            if (slot.isPlanned) ...<Widget>[
              // One row where there were two.
              //
              // `Choose another topic` set the topic and left the length, and
              // `A different plan` changed both without asking. Neither could
              // express "same idea, shorter", which is the thing a reader
              // actually wants — so the topic, the lens and the length became
              // one question, asked once.
              _menuRow('Change it', 'free', () async {
                Navigator.of(ctx).pop();
                await _changeIt(q, index);
              }),
              _menuRow('Draw another plan', 'free', () async {
                Navigator.of(ctx).pop();
                _reroll(q, index);
              }),
            ] else ...<Widget>[
              // Both of these are CLOSED when there is no text to open. A ready
              // slot can lose its body two ways — the reader freed the bytes, or
              // the article predates bodies being stored — and in both cases
              // `Read it` opened an empty page. The card no longer offers Read
              // either; the honest rows are the two below.
              if ((slot.article?.sentences.isNotEmpty) ?? false) ...<Widget>[
                _menuRow('Read it', '', () {
                  Navigator.of(ctx).pop();
                  _openArticle(slot);
                }),
                _menuRow('Listen to it', '', () {
                  Navigator.of(ctx).pop();
                  setState(() {
                    _openId = slot.articleId;
                    _listeningOn = true;
                    _tab = Dest.article;
                  });
                }),
              ] else
                _menuRow('The text is gone',
                    'its words are not on this phone any more',
                    () => Navigator.of(ctx).pop()),
              // This row used to call `_write`, which begins `if (!slot.isPlanned)
              // return` — so on a READY card it always returned immediately and
              // the menu item did nothing at all. Silently. `_writeAgain` first
              // asks what the NEW piece should be (subject, instruction, length),
              // then retires the old article — free, into the library, counts
              // intact, and never counted as a read — and only then pays.
              _menuRow('Write a new one', 'the old one is kept', () async {
                Navigator.of(ctx).pop();
                await _writeAgain(q, index);
              }),
              // The subtitle answers the one question a reader has, looking at a
              // card they finished: "if I say done, do I lose it?" Two facts,
              // one line — what happens to the ARTICLE (kept, reopenable) and
              // what happens to the SLOT (a free plan takes it).
              //
              // This row stays available on an article that has been read.
              // Reading is not being done with something — the app's whole
              // position is that a read-through is a beginning — so a reader who
              // has read this twice may still want it out of the way, and the
              // card shows `read 2×` right above this menu so the choice is an
              // informed one.
              _menuRow('Done with it', 'kept in your library', () async {
                Navigator.of(ctx).pop();
                await _doneWithIt(q, index);
              }, danger: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _menuRow(String title, String sub, VoidCallback onTap,
      {bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: TypeScale.sans,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: danger
                              ? context.colors.verm
                              : context.colors.ink,
                        ),
                      ),
                      if (sub.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          style: TextStyle(
                            fontFamily: TypeScale.sans,
                            fontSize: 11.5,
                            color: context.colors.ink3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text('›',
                    style: TextStyle(
                        fontSize: 18, color: context.colors.ink3)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "Done with it" archives the article and puts a PLAN in its place. Free,
  /// and it never destroys anything — the shelf keeps the row and the counts.
  Future<void> _doneWithIt(Queue q, int index) async {
    // THE LAST-ONE GUARD, and it is the other half of a promise made at the top
    // of this file: whatever happens, at least one NEW article is waiting for
    // you. `Done with it` frees a slot and puts a PLAN in it — which is the right
    // outcome for a queue holding two ready cards, and the wrong outcome for a
    // queue holding one, because it leaves three dashed cards and nothing to
    // read. The reader would open the app to a queue with no article in it.
    //
    // Not a lock on the action, a lock on the moment: write the next one, or
    // read this one again, and the row comes back.
    if (q.readyCount <= 1) {
      Toast.show(context,
          'that is your last one · write the next, or read this again first');
      return;
    }
    final Article? retired = q.retireReadySlot(index, _freePlan());
    if (retired == null) {
      Toast.show(context, 'that one is only planned — write it first');
      return;
    }
    // Archive it BEFORE the queue is saved. `retireReadySlot` promises the
    // caller writes a ledger row, and skipping that made a shelved article
    // vanish from the library the moment its slot was reused — a reader who
    // said "done" lost the only copy of something they had paid for. This is
    // NOT a read and NOT a listen: counts stay at whatever they were.
    try {
      await _repo.recordLedger(
        articleId: retired.id,
        title: retired.title,
        keywords: retired.keywords,
        day: todayDay(),
        kilobytes: (retired.wordCount * 6 ~/ 1024) + 1,
      );
    } catch (e) {
      debugPrint('the article could not be archived: $e');
    }
    await _repo.saveQueue(q);
    setState(() {});
    // The same promise `_retireAndRefill` keeps: saying "done" must never leave
    // the queue with nothing the reader has yet to meet. The write is gated, so
    // with automatic writing off the plan simply waits for a tap.
    if (!await _hasUnreadCard(q)) {
      unawaited(_maybeAutoWrite());
    }
    Toast.show(context,
        '${retired.title} is in your library · not counted as a read');
  }

  /// [isLearned] is the domain's definition; this only adapts the record to
  /// its named arguments.
  static bool _isLearned(({int reads, int listens}) c) =>
      isLearned(reads: c.reads, listens: c.listens);

  /// Retire [articleId] if it is learned; otherwise leave it alone.
  ///
  /// Called after every count and on boot. Counts are read from the database
  /// rather than inferred from the tap that just happened, because the second
  /// half of the pair may have happened in an earlier session.
  Future<void> _maybeRetireLearned(String articleId) async {
    try {
      final Map<String, ({int reads, int listens})> counts =
          await _repo.countsFor(<String>[articleId]);
      final ({int reads, int listens}) c =
          counts[articleId] ?? (reads: 0, listens: 0);
      if (!_isLearned(c)) return;
    } catch (e) {
      debugPrint('the learned check could not read the counts: $e');
      return;
    }
    await _retireAndRefill(articleId);
  }

  /// Retire every card in the queue that has already been learned, then make
  /// sure something new is on its way.
  ///
  /// This is the repair pass. It runs on cold launch and on resume, because
  /// the live path can be interrupted — a killed process between the count and
  /// the queue write, or a queue inherited from a build whose "finished" rule
  /// was different — and a repair pass is the only thing that turns that state
  /// back into a queue. It is idempotent and free until the final write, which
  /// goes through the same gated automatic path as every other write.
  Future<void> _reconcileQueue() async {
    final Queue? q = _queue;
    if (q == null) return;
    bool changed = false;
    try {
      final Map<String, ({int reads, int listens})> counts =
          await _repo.countsFor(<String>[
        for (final QueueSlot s in q.slots)
          if (s.isReady) s.articleId,
      ]);
      for (int i = 0; i < q.slots.length; i++) {
        final QueueSlot s = q.slots[i];
        if (!s.isReady || s.isWriting) continue;
        final ({int reads, int listens}) c =
            counts[s.articleId] ?? (reads: 0, listens: 0);
        if (!_isLearned(c)) continue;
        final Article? retired = q.retireReadySlot(i, _freePlan());
        if (retired == null) continue;
        changed = true;
        try {
          await _repo.recordLedger(
            articleId: retired.id,
            title: retired.title,
            keywords: retired.keywords,
            day: todayDay(),
            kilobytes: (retired.wordCount * 6 ~/ 1024) + 1,
          );
        } catch (e) {
          debugPrint('the article could not be archived: $e');
        }
      }
    } catch (e) {
      debugPrint('the queue could not be reconciled: $e');
    }
    if (changed) {
      try {
        await _repo.saveQueue(q);
      } catch (e) {
        debugPrint('the reconciled queue could not be saved: $e');
      }
      if (mounted) setState(() {});
    }
    // ALWAYS AT LEAST ONE UNTOUCHED ARTICLE. `_maybeAutoWrite` turns the first
    // waiting plan into a ready card — which is what makes the queue's promise
    // true again after a learned card left. It still has the last word: off, no
    // key or a full month means the plan card waits for the reader rather than
    // the app spending on its own. Calling it when there IS already something
    // untouched is harmless: it only ever writes a PLANNED card.
    final bool hasUnread = await _hasUnreadCard(q);
    if (!hasUnread || q.hasPlannedSlot) {
      await _maybeAutoWrite();
    }
  }

  /// LEARNED: confirmed read AND full listen. The card becomes a plan, and
  /// something untouched is guaranteed to be waiting.
  ///
  /// WHY THIS IS NOT `_doneWithIt`. That method is the reader saying "I am done
  /// with this" — a deliberate act on one card, guarded by a last-one check so
  /// a curious tap cannot empty the queue. This is the app noticing that the
  /// reader finished something, which is not a decision and must not be
  /// refusable: a queue of three articles all read and heard is the state in
  /// the bug report, and nothing in the app would ever have changed it.
  ///
  /// The last-one guard is therefore deliberately ABSENT here. The order of the
  /// steps below is what makes that safe: the plan is installed FIRST, so
  /// there is never a moment with fewer cards, and a write is started only if
  /// the queue has nothing untouched left.
  ///
  /// FREE. Installing a plan costs nothing; the write that may follow is the
  /// same gated write a tap would start.
  Future<void> _retireAndRefill(String articleId) async {
    final Queue? q = _queue;
    if (q == null) return;
    final int index = q.slots.indexWhere(
      (QueueSlot s) => s.articleId == articleId,
    );
    if (index < 0) return; // not in the queue right now — nothing to retire
    if (!q.slots[index].isReady) return; // already a plan
    if (q.slots[index].isWriting) return; // a write is landing in it

    final Article? retired = q.retireReadySlot(index, _freePlan());
    if (retired == null) return;
    // The ledger row first, exactly as `_doneWithIt` does it: `retireReadySlot`
    // promises the caller writes one, and skipping it made a shelved article
    // vanish from the library the moment its slot was reused. This is NOT a
    // read and NOT a listen — the counts stay wherever the reader put them.
    try {
      await _repo.recordLedger(
        articleId: retired.id,
        title: retired.title,
        keywords: retired.keywords,
        day: todayDay(),
        kilobytes: (retired.wordCount * 6 ~/ 1024) + 1,
      );
    } catch (e) {
      debugPrint('the article could not be archived: $e');
    }
    await _repo.saveQueue(q);
    if (!mounted) return;
    setState(() {});

    // THE GUARANTEE: at least one card in the queue is something the reader has
    // never met. Without it the queue fills with read articles again and the
    // reader is back where they started, which is the whole complaint.
    if (!await _hasUnreadCard(q)) {
      unawaited(_maybeAutoWrite());
    }
  }

  /// Whether any card in the queue is ready and has never been read or heard.
  ///
  /// Counts come from the database rather than from memory, because the whole
  /// point of the check is that it cannot be fooled by a stale number: a card
  /// the reader finished in an earlier session has to count as met.
  Future<bool> _hasUnreadCard(Queue q) async {
    try {
      final Map<String, ({int reads, int listens})> counts =
          await _repo.countsFor(<String>[
        for (final QueueSlot s in q.slots) s.articleId,
      ]);
      for (final QueueSlot s in q.slots) {
        if (!s.isReady) continue;
        final ({int reads, int listens}) c = counts[s.articleId] ??
            (reads: 0, listens: 0);
        if (c.reads == 0 && c.listens == 0) return true;
      }
      return false;
    } catch (e) {
      debugPrint('the queue counters could not be read: $e');
      // Unreadable counts: assume there IS something new. The failure mode of a
      // wrong "yes" is a card the reader has met, which they can retire with
      // one tap. The failure mode of a wrong "no" is a paid write nobody asked
      // for, and this app does not spend money on a guess.
      return true;
    }
  }

  /// Change a planned card: what it is about, and how long.
  ///
  /// Nothing is applied until the sheet comes back with an answer. A reader who
  /// opens it and backs out has changed nothing, which is what "cancel" has to
  /// mean in a panel that edits two things at once.
  ///
  /// The saved instructions are read HERE rather than held in state, because
  /// they change from the settings screen and a cached copy would go stale the
  /// first time the reader edited one. Ten of them, newest-used first — the
  /// sheet is a picker, not the manager.
  Future<void> _changeIt(Queue q, int index) async {
    // THE GUARD THAT WAS MISSING.
    //
    // `_reroll` has always had one — a reroll replaces the very plan the write
    // in flight is using, so the article would come back for a topic the card no
    // longer shows. `_changeIt` edits the same two fields for the same reason
    // and did not have one: a reader who opened the sheet while a write was in
    // the air got their edit applied to a card whose article was already paid
    // for and about to overwrite it. Silently — the request went out, the money
    // was spent, and the article that landed was not the one they had just
    // described.
    //
    // Same guard, same sentence, same place. The ⋯ menu also reaches this method
    // and is not itself gated, which is exactly why it lives here and not in the
    // two callers.
    if (q.slots[index].isWriting) {
      Toast.show(context, 'a write is in flight · it lands in a moment');
      return;
    }

    final List<Instruction> saved =
        await _repo.instructions(limit: kRecentInstructions);
    if (!mounted) return;

    final QueueSlot slot = q.slots[index];
    final PlanRequest? req = await AppSheet.show<PlanRequest>(
      context,
      builder: (BuildContext ctx) => RegenerateSheet(
        initialInstruction: slot.instruction,
        initialInstructionId: slot.instructionId,
        initialBand: slot.plannedBand,
        initialWords: slot.plannedWords,
        plan: _plan,
        instructions: saved,
        // The manager, one tap away. The sheet is popped first by the sheet
        // itself, so this lands on a plain settings page rather than a stack of
        // two sheets.
        onSeeAll: () => _push(() => _settings(pane: Pane.instructions)),
      ),
    );
    if (req == null || !mounted) return;

    // A random draw is resolved HERE, once, and written onto the card — not
    // re-drawn on every rebuild, which would make the card's own length change
    // under the reader's eyes.
    final LengthBand band = req.random ? _randomBand() : req.band;
    final int words =
        band == LengthBand.custom ? req.exactWords : _plan.wordsFor(band);

    // A suggestion stays a suggestion only while its text is unchanged. An
    // edited sentence is the reader's instruction, not the app's proposal, and
    // the card's note has to say which one it is.
    final bool stillSuggested = slot.isSuggested &&
        req.instruction.trim() == slot.instruction.trim() &&
        req.instructionId == null;
    q.editPlan(
      index,
      instruction: req.instruction,
      instructionId:
          stillSuggested ? slot.instructionId : req.instructionId,
      // `fromSaved` is what keeps a non-null id; without it, picking a saved
      // instruction in this sheet silently dropped its id and the manager's
      // "most recently used" order never moved.
      fromSaved: stillSuggested || req.instructionId != null,
      words: words,
      band: band,
    );
    await _repo.saveQueue(q);
    if (!mounted) return;
    setState(() {});
    Toast.show(context, 'plan updated · nothing written, nothing paid');
  }

  /// Write a ready card again.
  ///
  /// The old article is RETIRED first: it goes to the library with its read and
  /// listen counts intact, and a fresh plan takes its slot. That is the same
  /// move `Done with it` makes, and it is free — so the reader pays for exactly
  /// one thing, which is the new article.
  ///
  /// Doing it in this order matters. Writing first and retiring afterwards
  /// would put two articles in one slot for the length of a network call, and
  /// the second one would silently overwrite the first if the retire then
  /// failed.
  Future<void> _writeAgain(Queue q, int index) async {
    // The replacement is drawn FIRST, so the sheet can show the reader what the
    // new card would otherwise be about. "Write a new one" with an empty box
    // asks the reader to invent a subject on the spot while the old article is
    // still on screen; a suggestion is something to accept, edit, or reject.
    final QueueSlot replacement = _freePlan();
    // Ask before anything is retired or paid for. The old article is still on
    // screen while the sheet is open, and a reader who backs out has changed
    // nothing and spent nothing — which is what cancel has to mean.
    final List<Instruction> saved =
        await _repo.instructions(limit: kRecentInstructions);
    if (!mounted) return;
    final PlanRequest? req = await AppSheet.show<PlanRequest>(
      context,
      builder: (BuildContext ctx) => RegenerateSheet(
        initialInstruction: replacement.instruction,
        initialInstructionId: replacement.instructionId,
        initialBand: replacement.plannedBand,
        initialWords: replacement.plannedWords,
        plan: _plan,
        instructions: saved,
        onSeeAll: () => _push(() => _settings(pane: Pane.instructions)),
      ),
    );
    if (req == null || !mounted) return;

    final Article? retired = q.retireReadySlot(index, replacement);
    if (retired == null) {
      // Planned already — the row should not have been offered, but a menu is
      // not a lock and this is one line.
      await _write(q, index);
      return;
    }
    try {
      await _repo.recordLedger(
        articleId: retired.id,
        title: retired.title,
        keywords: retired.keywords,
        day: todayDay(),
        // It already has a real size on the ledger from when it was written;
        // `recordLedger` keeps the existing one rather than overwriting it, so
        // this is only a fallback for a row that somehow has none.
        kilobytes: (retired.wordCount * 6 ~/ 1024) + 1,
      );
      await _repo.saveQueue(q);
    } catch (e) {
      debugPrint('the old article could not be archived: $e');
    }
    if (!mounted) return;
    // The reader's new subject lands on the REPLACEMENT plan before the write,
    // so the article that comes back is about what they just asked for rather
    // than about whatever `_freePlan` happened to leave in the slot.
    final LengthBand band = req.random ? _randomBand() : req.band;
    final int words =
        band == LengthBand.custom ? req.exactWords : _plan.wordsFor(band);
    q.editPlan(
      index,
      instruction: req.instruction,
      instructionId: req.instructionId,
      // A saved instruction picked here must keep its id; `editPlan` drops
      // anything not marked `fromSaved`, and that silently stopped the
      // instruction manager from recording the use.
      fromSaved: req.instructionId != null,
      words: words,
      band: band,
    );
    await _repo.saveQueue(q);
    setState(() {});
    await _write(q, index);
  }

  /// Open a ready card. A planned card has nothing to open, so this is never
  /// reached from one.
  void _openArticle(QueueSlot slot, {bool fromLibrary = false}) {
    // Hydrate FIRST. The queue holds a database stub — an identity and a title,
    // no body — and the bundled sample's text lives only in `_samples`. The card
    // already renders a hydrated copy, so it offered `Read` and this function
    // then bailed on the unhydrated stub: the button looked alive and did
    // nothing at all. Every caller goes through here, so the fix belongs here.
    slot = _hydrated(slot);
    // Zeroed before the load lands, so the previous article's numbers are never
    // shown against this one for a frame.
    _readsToday = 0;
    _readsInAll = 0;
    unawaited(_loadReadCounts(slot.articleId));
    // A slot with no body is not openable, and the card and the menu both know
    // that already — this is the third lock on the same door, because opening
    // onto an empty page is the one outcome the app must never produce.
    if (slot.article == null || slot.article!.sentences.isEmpty) return;
    setState(() {
      _openId = slot.articleId;
      _openFromLibrary = fromLibrary;
      _listeningOn = false;
      _speakingIndex = -1;
      _tab = Dest.article;
    });
  }

  /// A slot carrying the REAL article, not the database stub.
  ///
  /// The queue row only knows an identity, so its Article has a title of
  /// "a-sample-pointers" and zero words — which is the database talking to the
  /// reader. The body is already in memory from the bundle, so the card is
  /// filled in here rather than by adding two more columns to the ledger, which
  /// would duplicate a fact the article itself already states.
  QueueSlot _hydrated(QueueSlot slot) {
    final Article? a = slot.article;
    if (a == null) return slot;
    // Only fill in a MISSING body. A real body always wins over the bundle:
    // `_samples` is keyed by the sample's own id, and if that id is ever reused
    // for a written article (it used to be, because retiring a slot kept its
    // id) this lookup would silently replace the reader's article with the
    // sample. Prefer what is actually in the slot.
    if (a.sentences.isNotEmpty) return slot;
    final Article? full = _samples[slot.articleId]?.toArticle();
    if (full == null) return slot;
    return QueueSlot(
      articleId: slot.articleId,
      state: slot.state,
      article: full,
      instruction: slot.instruction,
      instructionId: slot.instructionId,
      plannedWords: slot.plannedWords,
      plannedBand: slot.plannedBand,
      isWriting: slot.isWriting,
    );
  }

  /// The full article behind an identity, from wherever it actually is.
  ///
  /// Three places, and the third one was missing: a bundled sample carries its
  /// own text, an article written in THIS session is in `_written`, and an
  /// article written in an EARLIER session is only in its queue slot, hydrated
  /// from `article_rows` at boot.
  ///
  /// Without the third lookup, tapping `Read` on a written card after a restart
  /// set `_openId` correctly and then found nothing — so the Article tab fell
  /// back to "the first ready slot", which is the bundled sample. The reader
  /// tapped an article they had paid for and got a different one. The card was
  /// right, the button was right, and the screen was wrong.
  Article? _articleFor(String id) {
    // Real bodies first, bundle last. `_samples` used to be checked first, so
    // a written article that had inherited the sample's id was invisible: every
    // open showed the sample instead of the article the reader had just paid
    // for. The sample is a fallback for an id nothing else claims, never an
    // override of something that was actually written.
    final Article? written = _written[id];
    if (written != null && written.sentences.isNotEmpty) return written;
    for (final QueueSlot s in _queue?.slots ?? const <QueueSlot>[]) {
      if (s.articleId == id && s.article != null && s.article!.sentences.isNotEmpty) {
        return s.article;
      }
    }
    final Article? sample = _samples[id]?.toArticle();
    if (sample != null) return sample;
    if (written != null) return written;
    for (final QueueSlot s in _queue?.slots ?? const <QueueSlot>[]) {
      if (s.articleId == id) return s.article;
    }
    return null;
  }

  /// Articles this phone paid for, kept in memory for the session. The body is
  /// NOT in the database: only its identity and counts are, which is what lets a
  /// written article be re-opened without a second copy of the text in two
  /// places.
  final Map<String, Article> _written = <String, Article>{};

  /// SINGLE FLIGHT, held on the shell rather than on a slot.
  ///
  /// The slot's own `isWriting` flag cannot be the lock, for two separate
  /// reasons, and both of them bite:
  ///
  ///  1. **It is persisted.** `_persistSlots` writes `isWriting: Value(s.isWriting)`
  ///     verbatim, and every other action calls `saveQueue` — `Done with it` on
  ///     another card, a reroll, an edit, a picture's intent line. Any of those
  ///     landing mid-flight persists a `true` that is not true any more, and a
  ///     process that dies right after restores it in `loadQueue`. The card then
  ///     reads "Writing…" forever, with Write it, ↻, ▣ and Change it all dead,
  ///     and the only way out is clearing the app's data. A lock that survives
  ///     the process is not a lock, it is a brick.
  ///  2. **A check-then-await-then-set is not a check at all.** Two callers
  ///     entering the same window both read `false`.
  ///
  /// So: claim and test in one expression with no `await` between them, keep it
  /// off the disk, and clear it on EVERY exit from `_write` — success, refusal,
  /// no-key and crash. `_releaseWrite` is that clearing, and it is deliberately
  /// idempotent because the exits are many.
  bool _writeClaim = false;

  /// True when this call took the lock. See [_writeClaim].
  bool _claimWrite() => !_writeClaim && (_writeClaim = true);

  /// Give the lock back. Safe to call twice, and on paths that never held it.
  void _releaseWrite() {
    _writeClaim = false;
  }

  /// THE ONLY PATH THAT COSTS MONEY.
  ///
  /// [pictures] is the reader's photographs, already shrunk. It defaults to
  /// empty because most writes have none — a card tapped with nothing attached
  /// must behave exactly as it always has.
  ///
  /// [auto] marks a write the app started by itself rather than one the reader
  /// tapped. It changes two things and nothing else: a refusal is SILENT (there
  /// is nobody standing there to tell, and a toast about a write the reader never
  /// asked for is noise), and the receipt says `auto` so the reader can tell
  /// which of today's articles they chose. It does not change the cost, the
  /// budget, the prompt or the article.
  Future<void> _write(
    Queue q,
    int index, {
    List<Picture> pictures = const <Picture>[],
    bool auto = false,
  }) async {
    QueueSlot slot = q.slots[index];
    if (!slot.isPlanned) {
      Toast.show(context, 'that one is already written');
      return;
    }
    // CLAIM THE SLOT FIRST, BEFORE ANYTHING IS AWAITED.
    //
    // This is the guard, and it is not a check — it is the check followed by the
    // mutation, with no `await` between them. That gap is the whole bug: the
    // old code checked `isWritingAnywhere` and then awaited the key twice
    // (reidentify, `_keys.writer()`) before setting `isWriting = true`. Two
    // callers entering that window — two taps, or the app's own automatic write
    // racing the reader's — both read `false`, both walked on, and both reached
    // the paid call. Two charges for one article, and the second overwrote the
    // first. A disabled button is a UI fact; this is the only thing that is a
    // fact about the code, so it has to be atomic.
    //
    // Claiming with a FIELD on the shell rather than with the slot's own flag,
    // because the slot's flag is persisted (`isWriting: Value(s.isWriting)`) and
    // any other action's `saveQueue` writes a mid-flight `true` into the
    // database. See `_writeClaim`.
    if (!_claimWrite()) {
      // Silent for an automatic write: nobody asked for it, so nobody needs to
      // be told it did not happen.
      if (!auto) {
        Toast.show(context,
            'another article is being written · it lands in a moment');
      }
      return;
    }

    // Never write a paid article under a bundled sample's id.
    //
    // Older builds kept a slot's id when a ready card was retired, so a sample
    // slot could be reused for real writes. The write then landed under
    // `a-sample-pointers` and every lookup preferred the bundle, so the reader
    // paid for an article they could never open. Mint a fresh id instead of
    // producing another shadowed write.
    //
    // AND GUARDED, because this `saveQueue` is the one write in `_write` that
    // sits between the claim and the first `try`. A `SqliteException(5)`
    // here — which this app has actually hit, see the note in `_boot` —
    // propagated straight out of `_write`, so `_releaseWrite` was never
    // reached and `_writeClaim` stayed `true` for the life of the process.
    // Every later Write it then hit `!_claimWrite()` and said "another article
    // is being written", and `_mayAutoWrite` refused to spend for the same
    // reason. Nothing recovered it but a restart. A lock that a failed disk
    // write can turn into a brick is the bug this project just finished fixing
    // in another form, so it gets the same treatment: catch, put the card back,
    // and hand the lock back.
    if (_samples.containsKey(slot.articleId)) {
      try {
        q.reidentify(index, _freePlan().articleId);
        await _repo.saveQueue(q);
        slot = q.slots[index];
      } catch (e) {
        debugPrint('the slot could not be re-identified: $e');
        _releaseWrite();
        if (!mounted) return;
        Toast.show(context,
            'this phone could not update the queue · nothing was spent',
            duration: const Duration(seconds: 6));
        return;
      }
    }

    final String? key = await _keys.writer();
    if (key == null || key.trim().isEmpty) {
      // An AUTOMATIC write with no key is silent. Nobody asked for it, and the
      // old path opened Settings and showed a toast on every launch — a reader
      // who had deliberately not configured a writer got an unexplained screen
      // they never requested. A manual tap still explains itself and offers
      // the place to fix it.
      if (auto) {
        _releaseWrite();
        return;
      }
      Toast.show(context, 'no writer key is saved — nothing was spent');
      _push(_settings);
      // Nothing was claimed and nothing was spent, so nothing is released
      // either — but the claim was taken above and a reader who saves a key in
      // Settings and comes back must find the card writable.
      _releaseWrite();
      return;
    }

    // The reader's own base URL and model, not the const provider defaults.
    final WriterEndpoint ep = _writerEndpoint;

    // THE PICTURE GATE, and it is before the key check is spent rather than
    // after — a text-only model answers a content array with
    // `400 unknown variant image_url`, having never read the picture and having
    // charged nothing. Sending it anyway would be paying for a request that
    // could not have worked, which is the one failure this app refuses to have.
    //
    // The refusal is a SENTENCE that names the alternatives, because a reader
    // holding a photograph of a word list and a toast that says "unsupported"
    // has been left with nowhere to go.
    if (pictures.isNotEmpty && !ep.supportsVision) {
      Toast.show(context, ep.visionRefusal, duration: const Duration(seconds: 6));
      _releaseWrite();
      return;
    }

    // The card shows it is working, so a tap cannot become a second call while
    // the first is still in flight. Set HERE as well as in `_claimWrite`: the
    // claim is what makes the code safe, and this is what makes the CARD show
    // it — the two exits above happen before any paid call and release the
    // claim so a retry is not silently dead.
    q.slots[index].isWriting = true;
    setState(() {});

    // ── the research, assembled before the write ────────────────────────
    //
    // Every line of this is free. The hotboard is one request to uapis.cn that
    // costs nothing; the recent titles come out of this phone's own database;
    // the met words come out of the word pool. The only paid call is the write
    // itself, and NOTHING HERE CAN FAIL IT — a source that does not answer is
    // simply not consulted, and the article is written from what the model
    // already knows.
    //
    // This is also where the cost line's honesty is decided: with no source
    // configured, `tools` comes out empty, no loop is built, and the write is
    // the single call the card promised.
    //
    // WRAPPED ANYWAY, and not because any of it is expected to throw. The claim
    // was taken at the top of this method and this block is still ahead of the
    // first `try`, so an exception from ANY line here — a keystore that refuses,
    // a database that is locked, a word pool that fails to decode — escapes
    // `_write` entirely and leaves `_writeClaim` true for the life of the
    // process. Every later write then says "another article is being written"
    // and the automatic write refuses to spend, with no way back but a restart.
    // One catch around the free work is far cheaper than that.
    final AgentLoop? agent;
    final List<NewsItem> news;
    final List<String> recent;
    final List<String> met;
    final List<String> mustUse;
    try {
      agent = await _buildAgent(ep, key);
      news = _newsForThisWrite;
      recent = await _recentTitles();
      final String day = todayDay();
      // Starred words that still owe showings are a PROMISE; the rest of the
      // crucial list is an offer. They are sent as two lists so the writer
      // cannot read "use four to six of these" over a word the reader has
      // starred twice and still owes three showings.
      mustUse = <String>[
        for (final WordEntry w
            in _pool?.starredDue(day) ?? const <WordEntry>[])
          w.lemma,
      ];
      final Set<String> promised = mustUse.toSet();
      met = <String>[
        for (final WordEntry w
            in _pool?.crucial(day) ?? const <WordEntry>[])
          if (!promised.contains(w.lemma)) w.lemma,
      ];
    } catch (e) {
      debugPrint('the research could not be assembled: $e');
      _failWrite(q, index, 'nothing was written · the sources would not answer');
      return;
    }
    if (!mounted) {
      _releaseWrite();
      return;
    }

    // The call and the saving are handled separately, because they fail for
    // different reasons and only one of them means "nothing was written". A
    // single catch-all reported a failed SAVE as a failed WRITE, which tells
    // the reader their money bought nothing when in fact the article is on
    // screen in front of them.
    AgentResult? ran;
    final Article article;
    try {
      article = await _writer.write(
        articleId: slot.articleId,
        instruction: slot.instruction,
        plan: _plan,
        // The number the card is showing, which is the number the reader agreed
        // to. `_plan.wordsFor` is the fallback for a slot stored by an older
        // build with no length on it.
        words: slot.plannedWords > 0
            ? slot.plannedWords
            : _plan.wordsFor(slot.plannedBand),
        apiKey: key,
        endpoint: ep,
        news: news,
        recentTitles: recent,
        metWords: met,
        mustUseWords: mustUse,
        pictures: pictures,
        agent: agent,
        onResult: (AgentResult r) => ran = r,
      );
    } on RemoteFailure catch (e) {
      // The provider said no, or could not be reached. Nothing was spent, and
      // the card goes back to being tappable.
      _failWrite(q, index, e.message + e.cost);
      return;
    } catch (e) {
      _failWrite(q, index, 'nothing was written · $e');
      return;
    } finally {
      // Every exit from the paid call closes the sockets it opened — success,
      // refusal and crash alike. This is the `finally` that keeps a cancelled
      // request from leaking a connection.
      _closeSources();
    }

    // The instruction was used. Recording it is what makes the picker's order
    // mean anything — "most recently used" is a fact this line creates.
    final String? instructionId = slot.instructionId;
    if (instructionId != null && !isSuggestionId(instructionId)) {
      unawaited(_repo.touchInstruction(instructionId, todayDay()));
    }

    // The article exists from here on. A failure below is a STORAGE failure.
    _written[article.id] = article;
    q.writeSlot(index, article);
    // ONE transaction for body + ledger + card, or none of them. It used to be
    // three separate calls in a row, and a process dying between any two of them
    // — the app swiped out of the recents list, the system reclaiming memory —
    // left a half-landed article: a body with no card, so an entry in the
    // library that opens onto nothing, or a card with no ledger row, so a
    // readable card the library and the storage bar cannot see. Both are garbage
    // the reader has no way to clear from the interface.
    //
    // The third window — money spent and the response never received — is NOT
    // closed by this and cannot be. The request is already at the provider and a
    // local timeout says nothing about what they have billed. What this does
    // guarantee is that a paid article lands completely or leaves nothing behind.
    final int bytes;
    try {
      bytes = await _repo.landArticle(
        article: article,
        queue: q,
        slotIndex: index,
        title: article.title,
        keywords: article.keywords,
        day: todayDay(),
        // Ceiling, not floor: an article smaller than a kilobyte still costs a
        // kilobyte of the budget, and a bar that says "0 KB" next to an article
        // the reader can see is a bar nobody believes again. The estimate is
        // made HERE rather than inside the transaction because it is the
        // caller's figure of speech, and the real byte count comes back out.
        kilobytes: (article.wordCount * 6 ~/ 1024) + 1,
      );
    } catch (e) {
      // The transaction rolled back, so the article is NOT on this phone in any
      // form — no body, no card, no ledger row, and the card goes back to being
      // tappable rather than sitting there claiming an article that is not
      // there. The money WAS spent; that is the one window no code can close.
      debugPrint('the article could not be saved: $e');
      q.slots[index].isWriting = false;
      _releaseWrite();
      if (!mounted) return;
      setState(() {});
      Toast.show(
        context,
        '${article.title} was written, but could not be saved to this phone · '
            'the money was spent and nothing landed',
        duration: const Duration(seconds: 6),
      );
      return;
    }

    // The article landed and the slot is `ready`, so the lock goes back. Before
    // the `mounted` check, not after: an unmounted shell still has to leave the
    // world writable for the next one.
    _releaseWrite();
    // A star is kept countable. Only words that ACTUALLY appear in the landed
    // article give up one owed showing; a writer that ignored the instruction
    // leaves the promise intact for the next run. Settled after the article is
    // safely on disk, because a failed save bought the reader nothing and must
    // not quietly consume a showing they asked for.
    unawaited(_settleStarQuotas(mustUse, article));
    if (!mounted) return;
    setState(() {});
    // The call count is the REAL one, out of the loop. It used to say "one
    // call" unconditionally, which was true while the writer was a single
    // request and stopped being true the moment research was configured. A
    // price on screen has to be the price that was charged.
    final int calls = ran?.modelCalls ?? 1;
    final String callLine = calls == 1 ? 'one call' : '$calls calls';
    // The real size, measured rather than guessed, so the toast says what the
    // article actually cost on the phone. The ledger carries the same number.
    final String sizeLine = '${(bytes / 1024).ceil()} KB';
    // An automatic write says so. Not an apology and not a celebration — a
    // receipt, so that a reader looking at three new articles can tell which of
    // them they asked for. It is also the only place the monthly count is
    // incremented: on SUCCESS, never on the attempt, because a write that failed
    // spent nothing and must not push the reader towards their ceiling.
    if (auto) unawaited(_countAutoWrite());
    Toast.show(
      context,
      '${article.title} is ready · ~${article.wordCount} words · $callLine'
      ' · $sizeLine${auto ? ' · auto' : ''}',
    );
  }

  /// Turn each promised word's appearance into one delivered showing.
  ///
  /// The check is on the ARTICLE'S TEXT, not on the writer's obedience: a model
  /// that says "I used it" while never writing the word must not burn a
  /// promise. Matching is word-level and accepts ordinary inflections — see
  /// [textUsesWord].
  Future<void> _settleStarQuotas(
      List<String> promised, Article article) async {
    final WordPool? pool = _pool;
    if (pool == null || promised.isEmpty) return;
    final String text = <String>[
      article.title,
      for (final Sentence s in article.sentences) s.english,
    ].join(' ');
    final List<WordEntry> changed = <WordEntry>[];
    for (final String lemma in promised) {
      final WordEntry? e = pool[lemma];
      if (e != null && e.consumeShowing(text)) changed.add(e);
    }
    if (changed.isEmpty) return;
    for (final WordEntry e in changed) {
      try {
        await _repo.saveWordStar(e);
      } catch (err) {
        // Not fatal to the article: it is already on the phone. The word keeps
        // its in-memory state and the next write persists again.
        debugPrint('the star quota for ${e.lemma} could not be saved: $err');
      }
    }
    if (mounted) setState(() {});
  }

  // ── the automatic write ────────────────────────────────────────────────

  /// This month's automatic writes, and the ceiling on them.
  ///
  /// Stored as two settings rather than a new table because that is what they
  /// are: one counter and one preference. Reset by the month string, not by a
  /// scheduled job — the counter carries the month it belongs to, and a month
  /// that has changed is a counter that starts again. No cron, no migration.
  static const String _autoMonthKey = 'auto:month';
  static const String _autoCountKey = 'auto:count';

  /// How many articles the app may write by itself in one month.
  ///
  /// 60 is three a day for a full month, which is more than this queue can hold
  /// — the queue is three cards, so the app can only ever be one write behind.
  /// The number is a CEILING against a runaway bug, not a budget a reader is
  /// expected to reach.
  ///
  /// The dollar figures below are the CEILING per article — one paid call — and
  /// they understate a month on which research is configured, because a
  /// researched article is up to `kMaxModelCalls` of them. At the most expensive
  /// endpoint configured that is $3.00 rather than $0.60. Settings states the
  /// researched figure; this comment states the same one so the two cannot
  /// quietly disagree.
  ///
  /// When it is reached the app stops and says so ONCE. It does not retry, it
  /// does not ask again every launch, and it does not spend a cent more until
  /// the month turns or the reader raises it.
  static const int kAutoWriteMonthlyCeiling = 60;

  /// `2026-10`. The month this counter belongs to.
  static String _autoMonth([DateTime? now]) {
    final DateTime n = now ?? DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  /// Whether an automatic write is allowed right now. Cheap, and asks nothing.
  ///
  /// The four conditions, and each one is a reason the app must not spend:
  ///
  ///  1. **the reader left it on.** Off by nothing — it is on by default, and
  ///     Settings → Who writes turns it off in one tap.
  ///  2. **there is a plan to write.** Automatic writing only ever turns a
  ///     PLANNED card into an article. It never overwrites something ready and
  ///     never invents a subject the reader has not seen.
  ///  3. **nothing is already in flight.** Single flight, across the queue.
  ///  4. **the month is not full.** See [kAutoWriteMonthlyCeiling].
  ///
  /// A missing key is deliberately NOT a condition. A reader with no key gets
  /// nothing spent and no toast — the queue page already says a key is needed
  /// on every planned card, and a toast about it on every launch is noise.
  Future<bool> _mayAutoWrite(Queue q) async {
    if (!_autoWrite) return false;
    if (q.nextPlanned == null) return false;
    // The LOCK, not a picture of it. `q.isWritingAnywhere` reads the slot's
    // flag, which is a rendering fact; `_writeClaim` is the thing that actually
    // stops a second paid call. Checking the flag here would let an automatic
    // write queue up behind one that had not yet set its own flag.
    if (_writeClaim) return false;
    try {
      final String? month = await _repo.setting(_autoMonthKey);
      final String? count = await _repo.setting(_autoCountKey);
      final int used = month == _autoMonth() ? (int.tryParse(count ?? '') ?? 0) : 0;
      if (used >= kAutoWriteMonthlyCeiling) {
        // THE SENTENCE THAT WAS MISSING. The app refused to spend and said
        // nothing at all: the switch stayed ON, the row still said "60 of 60",
        // and a reader who had just flipped it on watched nothing happen and
        // concluded the app was broken. Every other refusal in this app has a
        // toast — no key, pictures refused, a write in flight, the last-one
        // guard — because a silent refusal reads as a dead button.
        //
        // ONCE, and "once" has to survive a restart, which an in-memory bool
        // cannot. The flag is a setting key, so a reader who relaunches into a
        // full month is not told again. It is cleared when the month turns, so
        // next month's first full day gets its one sentence.
        await _sayCeilingReachedOnce();
        return false;
      }
    } catch (e) {
      // Unreadable counter: do not spend. The failure mode of a wrong "0" is a
      // month of articles; the failure mode of a wrong "full" is a reader who
      // taps Write it, which the app still does perfectly well.
      debugPrint('the automatic-write counter could not be read: $e');
      return false;
    }
    return true;
  }

  /// Tell the reader the month is full, and only once.
  ///
  /// The "once" is a setting key rather than a field because it has to survive a
  /// restart: a reader who relaunches into a full month must not be told again
  /// what they were told yesterday. It is stamped with the month it belongs to,
  /// so the next month's first full day gets its sentence back.
  static const String _autoFullKey = 'auto:fullFor';

  Future<void> _sayCeilingReachedOnce() async {
    try {
      final String month = _autoMonth();
      if (await _repo.setting(_autoFullKey) == month) return;
      await _save(_autoFullKey, month);
      if (!mounted) return;
      Toast.show(
        context,
        'the automatic write has done its $kAutoWriteMonthlyCeiling for this '
            'month · your cards still write when you tap them',
        duration: const Duration(seconds: 7),
      );
    } catch (e) {
      debugPrint('the ceiling notice could not be recorded: $e');
    }
  }

  /// Count one automatic write. Called only after the article landed.
  ///
  /// TWO KEYS, ONE WRITE. These used to be two independent `setSetting` calls
  /// with nothing between them, and a process that died in that gap left the
  /// month stamped and the count stale — which `_mayAutoWrite` reads as "a new
  /// month, so zero used", quietly handing back a full 60. `_save` also
  /// swallowed its own failure, so the toast said "· auto" for a write that was
  /// never counted at all. Both keys now go in one transaction, and a failure
  /// propagates so the caller can stop claiming the write was counted.
  Future<void> _countAutoWrite() async {
    try {
      final String month = _autoMonth();
      final String? stored = await _repo.setting(_autoMonthKey);
      final int used =
          stored == month ? (int.tryParse(await _repo.setting(_autoCountKey) ?? '') ?? 0) : 0;
      await _repo.setSettings(<String, String>{
        _autoMonthKey: month,
        _autoCountKey: '${used + 1}',
      });
      if (!mounted) return;
      setState(() => _autoWriteUsed = used + 1);
    } catch (e) {
      debugPrint('the automatic-write counter could not be written: $e');
    }
  }

  /// Start the next article by itself, if the four conditions hold.
  ///
  /// Called from three moments, all of them the reader having just done
  /// something: finished a read, finished a listen, and came back to the app.
  /// NEVER from a timer and never from a background task — see the note on
  /// `_autoTick` below for why that is the whole point.
  Future<void> _maybeAutoWrite() async {
    final Queue? q = _queue;
    if (q == null || q.isEmpty) return;
    if (!await _mayAutoWrite(q)) return;
    final int i = q.nextPlannedIndex;
    if (i < 0) return;
    debugPrint('auto: writing the next article (slot $i)');
    await _write(q, i, auto: true);
  }

  // ── the research the writer may do ────────────────────────────────────

  /// The news list this write may draw on, fetched once per write.
  ///
  /// Held in a field rather than returned from [_buildAgent] because the list
  /// has TWO jobs: the tool reads a story out of it by index, and the prompt
  /// shows the model the thirty titles so it can pick without spending a turn.
  /// Passing the same list to both is what makes the index in the tool call
  /// mean the same thing as the index in the prompt.
  List<NewsItem> _newsForThisWrite = const <NewsItem>[];

  /// Build the loop, or return null when there is nothing to look anything up
  /// with. Null is the fast path, and it is the DEFAULT path — a reader who has
  /// configured nothing gets the single call the cost line promises.
  Future<AgentLoop?> _buildAgent(WriterEndpoint ep, String writerKey) async {
    _newsForThisWrite = const <NewsItem>[];
    final List<AgentTool> tools = <AgentTool>[];

    // Both clients are opened here and closed by `_closeSources`, because a
    // `Future.timeout` does not cancel the socket underneath it — a client that
    // is merely abandoned keeps a connection open behind the app's back.
    if (_newsOn) {
      final String? newsKey = await _keys.news();
      if (newsKey != null && newsKey.trim().isNotEmpty) {
        final NewsSource source = NewsSource();
        _openSources.add(source);
        try {
          _newsForThisWrite = await source.hotboard(apiKey: newsKey);
        } catch (e) {
          // A hotboard that does not answer is not a failure of the write. The
          // reader gets a free-choice article, which is what they would have
          // got with no key at all.
          AgentLog.instance.warn('plan', 'the news list was not available',
              detail: <String, Object?>{'error': '$e'});
        }
        if (_newsForThisWrite.isNotEmpty) {
          tools.add(ReadStoryTool(news: source, items: _newsForThisWrite));
        }
      }
    }

    if (_searchOn) {
      final String? searchKey = await _keys.search();
      if (searchKey != null && searchKey.trim().isNotEmpty) {
        final McpClient mcp = McpClient();
        _openSources.add(mcp);
        tools.add(WebSearchTool(mcp: mcp, apiKey: searchKey));
      }
    }

    if (tools.isEmpty) {
      // Nothing to look anything up with. Close what was opened for nothing —
      // the news client did one request and is now done.
      _closeSources();
      return null;
    }
    // The switch is read LIVE, on every iteration of the loop, through the
    // `cancelled` hook the loop already had and nobody passed. Turning
    // automatic writing off used to do nothing at all to a write already in the
    // air: `_write` never looked at `_autoWrite`, so a reader who flipped the
    // switch to stop the spending watched the article land a minute later, saw
    // the "· auto" toast, and found one more unit of the month gone. The switch
    // was ineffective for exactly the minute it was most likely to be used.
    //
    // What this does NOT do is refund the calls already made — the loop can only
    // decline the NEXT one. That is the honest limit and the toast says so.
    return AgentLoop(
      endpoint: ep,
      apiKey: writerKey,
      tools: tools,
      cancelled: () => !_autoWrite,
    );
  }

  /// Everything opened for one write, closed when it finishes. A list rather
  /// than named fields so there is one place to close and no way to add a
  /// source that leaks.
  final List<Object> _openSources = <Object>[];

  void _closeSources() {
    for (final Object s in _openSources) {
      if (s is NewsSource) s.close();
      if (s is McpClient) s.close();
    }
    _openSources.clear();
  }

  /// What the writer has recently produced, so it does not repeat itself.
  ///
  /// Best-effort: a database that cannot answer costs the writer its memory,
  /// not the article.
  Future<List<String>> _recentTitles() async {
    try {
      return await _repo.recentTitles();
    } catch (e) {
      AgentLog.instance
          .warn('plan', 'recent titles unavailable', detail: <String, Object?>{
        'error': '$e',
      });
      return const <String>[];
    }
  }

  /// Put a slot back the way it was and say why.
  ///
  /// The flag reset is the whole point: it was never cleared on the failure
  /// path, so one refused key or one dropped connection left the card reading
  /// "Writing…" for the rest of the session with a dead button on it.
  void _failWrite(Queue q, int index, String message) {
    if (index >= 0 && index < q.slots.length) {
      q.slots[index].isWriting = false;
    }
    _releaseWrite();
    if (!mounted) return;
    setState(() {});
    Toast.show(context, message, duration: const Duration(seconds: 6));
  }

  /// Reroll is free, needs no input, and never touches money.
  void _reroll(Queue q, int index) {
    // The card's ↻ is closed while a write is in flight, but the ⋯ menu reaches
    // the same method and is not. Guarding here rather than in both callers is
    // the difference between one place to get right and two.
    if (q.slots[index].isWriting) {
      Toast.show(context, 'a write is in flight · it lands in a moment');
      return;
    }
    // Never draw the subject that is already on the card: "another plan" that
    // says the same sentence is indistinguishable from a dead button.
    q.reroll(index, _freePlan(avoid: <String>[q.slots[index].instruction]));
    _repo.saveQueue(q);
    setState(() {});
    Toast.show(context, 'a different plan · nothing was paid for');
  }

  // ── pictures as an instruction ──────────────────────────────────────────

  /// The camera on a planned card. Two taps: attach, then write.
  ///
  /// WHY THIS IS NOT ONE TAP. The pictures have to be shrunk before anything is
  /// spent — a 12 MP photo is 4 MB and five of those base64'd is a request body
  /// several providers refuse outright — and shrinking takes a few hundred
  /// milliseconds of full-resolution decoding that must not happen while a paid
  /// call is in flight. So the sheet is where the reader sees the pictures, sees
  /// them get smaller, and confirms; the write is the next tap.
  ///
  /// WHY THE INTENT IS ASKED. "A good sentence", "a scene" and "a word list"
  /// produce three different articles from the same photograph, and only the
  /// reader knows which one they photographed. A model that has to guess will
  /// guess, and the reader pays for the guess. One chip is cheaper than an
  /// article about the wrong thing.
  Future<void> _withPictures(Queue q, int index) async {
    final QueueSlot slot = q.slots[index];
    if (!slot.isPlanned || slot.isWriting) return;

    final PictureRequest? req = await AppSheet.show<PictureRequest>(
      context,
      builder: (BuildContext ctx) => PictureSheet(
        // Whatever the card already says it is for. Not remembered across
        // launches — a picture instruction lives for one write, and so does the
        // answer to this question.
        intent: slot.instruction.trim().isEmpty
            ? null
            : _intentOf(slot.instruction),
        // The writer's ability is checked HERE rather than after the pictures
        // are picked, so a reader on a text-only model is told before they have
        // gone to their gallery and back.
        canSeePictures: _writerEndpoint.supportsVision,
      ),
    );
    if (req == null || req.isEmpty || !mounted) return;

    // The intent is written onto the card, and this is the ONLY thing that is
    // saved. The PICTURES are not — there is no table of blobs and nothing here
    // outlives the write; the reader already has them in their photo app. What
    // survives is the sentence saying what they were for, because a card that
    // says `Anything` while five photographs were attached to it is a card
    // lying about its own state.
    //
    // A reader who typed something keeps it: their words outrank the intent.
    // But an app SUGGESTION does not: the photograph is now the request, and
    // leaving "Why a mirror never swaps your left and right" above a word-list
    // screenshot would tell the writer to ignore the picture. The suggestion is
    // replaced, not overlaid.
    if (slot.instruction.trim().isEmpty || slot.isSuggested) {
      q.editPlan(index, instruction: 'from ${req.intent.short}');
      await _repo.saveQueue(q);
      if (!mounted) return;
      setState(() {});
    }

    // The pack is built HERE, and this is the only place in the app that builds
    // one. `PicturePack.of` is the object that enforces the two ceilings — five
    // pictures and 2 MB — and it was never called by anything, so a picture the
    // shrinker could not get under 2 MB went to the wire at full base64 price.
    // The ceiling is stated in the docs as an executable invariant; this line is
    // what makes that true.
    //
    // The refusal is a sentence and not a crash: a reader holding a panorama
    // needs to be told which picture is too big, not shown a dead screen.
    final List<Picture> packed;
    try {
      packed = PicturePack.of(req.pictures).pictures;
    } on StateError catch (e) {
      Toast.show(context, '$e · pick a smaller one', duration: const Duration(seconds: 6));
      return;
    }

    await _write(q, index, pictures: packed);
  }

  /// Which intent a stored instruction describes, if any.
  ///
  /// Written by [_withPictures] as `from a sentence` / `from a scene` /
  /// `from a word list`, and read back so the sheet opens with the answer
  /// already chosen. Matching on the string rather than a new column: a picture
  /// instruction is a sentence like any other, and adding a field to the queue
  /// table for a value that is already spelled out in the row would be the
  /// second copy of the truth this project refuses to keep.
  static PictureIntent? _intentOf(String instruction) {
    final String s = instruction.trim().toLowerCase();
    for (final PictureIntent i in PictureIntent.values) {
      if (s == 'from ${i.short}') return i;
    }
    return null;
  }

  // ── article ───────────────────────────────────────────────────────────

  bool _listeningOn = false;

  /// The Article tab. With nothing open it says so rather than showing a
  /// placeholder article, because an empty reading screen is not an invitation.
  Widget _articleTab(Queue q) {
    Article? open;
    if (_openId != null) open = _articleFor(_openId!);
    // fall back to the first ready slot, so the tab is never blank on purpose
    if (open == null) {
      for (final QueueSlot s in q.slots) {
        if (s.article != null) {
          open = _articleFor(s.articleId);
          break;
        }
      }
    }
    if (open == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Nothing written yet',
                style: TextStyle(
                  fontFamily: TypeScale.serif,
                  fontSize: 17,
                  color: context.colors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The queue is three plans. Write one and it will open here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: TypeScale.serif,
                  fontSize: 13.5,
                  height: 1.6,
                  color: context.colors.ink3,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return _articleViewSwitch(_articlePage(open), _listenPage(open));
  }

  Widget _listenPage(Article a) {
    return ListenScreen(
      article: a,
      player: _audio,
      onBack: _leaveArticle,
      hasAudio: _audio.hasRecordedAudio,
      // WHO is speaking, named as closely as the phone can manage.
      //
      // This is the label that has to carry the truth when a recording fails
      // mid-article: the device engine takes over, and a reader who hears the
      // narrator change deserves to be told rather than left wondering whether
      // they imagined it. The voice id and the chosen device voice are both
      // named, so "which one is this?" has an answer on screen.
      voiceLabel: _voiceLabel(),
      audioHandler: widget.audioHandler,
      size: _listenSize,
      onSize: (ListenSize s) {
        setState(() => _listenSize = s);
        unawaited(_save('ui:listenSize', s.label));
      },
      onCountListen: () => _countListen(a),
      autoPlay: _listenAutoPlay,
      active: _listeningOn,
      onWordTap: (String w) => _lookupWord(w, -1),
      listened: _listensInAll,
      onFinished: () => _onListenFinished(a),
      // Always wired. The ring is built from the shelf, so there is something to
      // go to unless the shelf is empty — and a button that appears and
      // disappears as the ring is rebuilt is a button the reader learns not to
      // trust. `_playNextArticle` is silent when it has nowhere to go.
      onNextArticle: _playNextArticle,
      endMode: _listenAutoContinue,
      endModeCount: _listenAutoContinueCount,
      onEndMode: _setListenEndMode,
    );
  }

  /// The player's "when it ends" chips write here. Same four values as the
  /// Settings key (`listen:autoContinue`), because the player and Settings are
  /// two faces of one preference rather than two preferences.
  void _setListenEndMode(String mode, int count) {
    setState(() {
      _listenAutoContinue = mode;
      _listenAutoContinueCount = count;
      // A count chosen mid-session takes effect NOW, not at next launch: the
      // reader is standing at the player deciding how many more, and "starts
      // counting from next app start" is a rule they would not expect.
      // `forever` never consults the counter; `off` and `loop` never
      // continue — `_onListenFinished` reads the mode first.
      if (mode == 'count') _autoContinueLeft = count;
    });
    unawaited(_save('listen:autoContinue', mode));
    unawaited(_save('listen:autoContinueCount', '$count'));
  }

  /// Listening counts as a LISTEN and never as a read. Conflating them would put
  /// a number on the shelf the reader did not earn by reading, and they would
  /// have no way to tell.
  /// GUARDED, like [_countRead] and unlike what this used to be.
  ///
  /// `_repo.countListen` was awaited with no `try` at all, and both callers are
  /// unawaited. A database failure therefore produced an unhandled async error
  /// with nothing on screen, `_listensInAll` never updated — and in
  /// `_onListenFinished` the exception aborted the method BEFORE the
  /// auto-continue block, so one failed count silently stopped the commute run.
  /// `_countRead` has had this guard the whole time; the two methods are the
  /// same shape and only one of them was defended.
  Future<void> _countListen(Article a) async {
    try {
      await _repo.countListen(
        articleId: a.id,
        title: a.title,
        day: todayDay(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {});
      Toast.show(context, 'that listen could not be counted · $e');
      return;
    }
    if (!mounted) return;
    Toast.show(context, 'counted a listen. reads untouched.');
    setState(() {});
    unawaited(_loadListenCounts(a.id));
    unawaited(_loadQueueCounts());
    // The other half of "learned". A listen on its own never retires a card:
    // the rule needs a confirmed read AND a full listen, and this checks both
    // from the database so a read from last week still counts.
    unawaited(_maybeRetireLearned(a.id));
  }

  /// One completed play-through. Counting lives HERE rather than on Play,
  /// because the rule is "a full listen counts, a start does not". An
  /// interrupted pass never reaches `onFinished`, so it is never counted.
  ///
  /// One completed play-through.
  ///
  /// Three things happen here, in this order, and the order is the design:
  ///
  ///  1. The listen is COUNTED. Money and record-keeping first, because a run
  ///     that continues past an uncounted article is a run the reader cannot
  ///     account for afterwards.
  ///  2. The card is REPLACED with a plan. An article that has been heard all
  ///     the way through is an article the reader has met, and a queue that
  ///     keeps offering it is a queue that has stopped being a queue. It goes
  ///     to the shelf — the row, the counts, everything but the slot.
  ///  3. Something NEW is guaranteed to be waiting. If the replacement left the
  ///     queue with nothing unread, a write starts. This is the only automatic
  ///     spending in the app and it is gated exactly as hard as a tap.
  ///
  /// `loop` never reaches here at all — the player wraps and keeps speaking —
  /// but the guard is kept so a future caller cannot accidentally fall into
  /// auto-continue while the reader asked for one article on repeat.
  Future<void> _onListenFinished(Article a) async {
    await _countListen(a);
    if (!mounted) return;
    // Heard all the way through — but a listen is only half of learned. The
    // card retires when the reader has ALSO confirmed a read; `_countListen`
    // already started that check, and awaiting it here keeps the queue change
    // ahead of the auto-continue decision below.
    await _maybeRetireLearned(a.id);
    if (!mounted) return;
    if (_listenAutoContinue == 'off' || _listenAutoContinue == 'loop') return;
    if (_listenAutoContinue == 'count') {
      if (_autoContinueLeft <= 0) return;
      _autoContinueLeft--;
    }
    final String? afterThis = await _peekNextListen();
    await _playNextArticle();
    if (afterThis == null) {
      // The ring ran out of anything to speak, which for a ring means the shelf
      // is empty or every article's bytes were freed. Writing one more is the
      // only way forward and it is gated by `_mayAutoWrite` exactly as a tap is.
      unawaited(_maybeAutoWrite());
    }
  }

  /// Remaining auto-continues this session when the mode is `count`.
  int _autoContinueLeft = 0;

  int _listensInAll = 0;

  /// Reads and listens per article, for the queue cards.
  ///
  /// Two numbers and never a sum: hearing an article on a bus is not reading it,
  /// and a card that showed only a total would be a card that says "you met this
  /// 5 times" about something read once and heard four.
  final Map<String, ({int reads, int listens})> _articleCounts =
      <String, ({int reads, int listens})>{};

  /// Zero for an article nothing is known about, which is the honest answer.
  ({int reads, int listens}) _countOf(String articleId) =>
      _articleCounts[articleId] ?? (reads: 0, listens: 0);

  /// Read the whole queue's counters in one query.
  ///
  /// Called after every count and after boot, so the card that was just counted
  /// changes under the reader's finger. Re-reading all three rather than
  /// incrementing the one in memory: the database is the source of truth, and a
  /// number the UI added itself is a number that can disagree with the row the
  /// History tab is built from.
  Future<void> _loadQueueCounts() async {
    final Queue? q = _queue;
    if (q == null) return;
    try {
      final Map<String, ({int reads, int listens})> fresh =
          await _repo.countsFor(<String>[
        for (final QueueSlot s in q.slots) s.articleId,
      ]);
      if (!mounted) return;
      setState(() => _articleCounts
        ..clear()
        ..addAll(fresh));
    } catch (e) {
      debugPrint('the queue counters could not be read: $e');
    }
  }

  /// Reads + listens for the article on screen, and the day it was last met.
  ///
  /// THE ORDERING NO LONGER READS THESE. The listening ring is built from the
  /// shelf, which already carries both numbers for every article the phone can
  /// speak — a cache of the open article's two numbers was a second source of
  /// truth for exactly one row of it, and it was stale for the other rows by
  /// definition. What remains here is what the Article screen shows.
  Future<void> _loadListenCounts(String articleId) async {
    try {
      final (int today, int total) = await _repo.readCounts(
        articleId: articleId,
        day: todayDay(),
      );
      final int listens = await _repo.ledgerListens(articleId);
      if (!mounted) return;
      setState(() {
        _readsToday = today;
        _readsInAll = total;
        _listensInAll = listens;
      });
    } catch (e) {
      debugPrint('listen counts unavailable: $e');
    }
  }

  /// Advance to the next article and start it. Silent when there is nothing.
  Future<void> _playNextArticle() async {
    final String? nextId = await _peekNextListen();
    if (nextId == null) return;
    final Article? next = _articleFor(nextId);
    if (next == null || next.sentences.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _openId = next.id;
      _listeningOn = true;
    });
    unawaited(_loadListenCounts(next.id));
    unawaited(_loadReadCounts(next.id));
  }

  /// The listening run: an ordered RING of everything the phone can speak.
  ///
  /// Built from the shelf, not from the three live slots. That is the whole
  /// difference between a run that keeps going and one that stops after three
  /// articles: the queue is rewritten underneath the run — a slot is retired, a
  /// write lands, the reader taps Done with it — and a picker that only sees
  /// the current three runs out of candidates the moment it has heard them all.
  ///
  /// Rebuilt on demand rather than cached, because the shelf is a query and a
  /// stale ring would offer an article whose slot has just been reused. One
  /// `await` on a local SQLite read is not a cost worth a cache invalidation
  /// bug.
  Future<ListenSequence?> _listenSequence() async {
    final Queue? q = _queue;
    if (q == null) return null;
    try {
      final Library lib = await _repo.library(q);
      return listenSequenceOf(lib.shelf());
    } catch (e) {
      debugPrint('the listening order could not be read: $e');
      return null;
    }
  }

  /// The next article to listen to, or null when nothing can be spoken.
  ///
  /// One step around the ring, so it never repeats an article until it has been
  /// all the way round — and it WRAPS, which is what makes a run not stop. The
  /// only thing that ends a run is the reader's own count (`count` end mode) or
  /// a tap on Stop.
  ///
  /// [current] is the article playing now, and it is excluded from the draw
  /// rather than from the ring: staying in the ring is what lets a run come
  /// back round to it, and taking it out of the ring entirely is what used to
  /// make the third article the last one.
  Future<String?> _peekNextListen() async {
    final ListenSequence? ring = await _listenSequence();
    if (ring == null || ring.isEmpty) return null;
    final String? current = _openId;
    final ListenSequence onNow =
        current == null ? ring : ring.on(current);
    final String? nextId = onNow.next(_listenOrder, todayDay());
    // The ring held exactly one article and it is the one playing. A run of one
    // is a run that has nowhere to go, and saying so is better than replaying
    // the same piece forever behind the reader's back.
    if (nextId == current) return null;
    return nextId;
  }

  /// Read or Listen. The prototype's segmented control; the indicator slides
  /// rather than the layout jumping.
  Widget _articleViewSwitch(Widget read, Widget listen) {
    return Column(
      children: <Widget>[
        Container(
          margin: const EdgeInsets.fromLTRB(Gap.gutter, 8, Gap.gutter, 0),
          height: 34,
          decoration: BoxDecoration(
            color: context.colors.paperSunk,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.colors.hair),
          ),
          child: Row(
            children: <Widget>[
              _seg('Read', !_listeningOn, () {
                unawaited(_audio.stop());
                setState(() {
                  _listeningOn = false;
                  _speakingIndex = -1;
                });
              }),
              _seg('Listen', _listeningOn,
                  () => setState(() => _listeningOn = true)),
            ],
          ),
        ),
        Expanded(
          // Both children stay alive, and the stack is keyed on the article.
          //
          // Swapping `_listeningOn ? listen : read` destroyed the Listen
          // screen every time the reader glanced at Read: the sentence index
          // reset to 0 and, with auto-play on, the article started over from
          // the top — the one thing a Listen tab must never do. An
          // IndexedStack keeps the state; the key makes a NEW article a fresh
          // screen rather than the previous one with its title swapped.
          child: IndexedStack(
            key: ValueKey<String>(_openId ?? 'none'),
            index: _listeningOn ? 1 : 0,
            children: <Widget>[read, listen],
          ),
        ),
      ],
    );
  }

  Widget _seg(String label, bool on, VoidCallback tap) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(9),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: TypeScale.sans,
                fontSize: 13,
                fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                color: on ? context.colors.ink : context.colors.ink3,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _articlePage(Article a) {
    return ArticleScreen(
      article: a,
      onBack: _leaveArticle,
      onWordTap: _lookupWord,
      onCountRead: () => _countRead(a),
      readsToday: _readsToday,
      readsInAll: _readsInAll,
      counting: _counting,
      speakingIndex: _speakingIndex,
      onSpeakSentence: (int i) => _speakSentence(a, i),
      fromLibrary: _openFromLibrary,
      readSize: _readSize,
      onReadSize: (ReadSize s) {
        setState(() => _readSize = s);
        unawaited(_save('ui:readSize', s.label));
      },
    );
  }

  /// Return to the Queue from any tab. The bottom bar already switches tabs, so
  /// this is only for the header labels.
  void _toQueue() => setState(() {
        _openId = null;
        _openFromLibrary = false;
        _listeningOn = false;
        _speakingIndex = -1;
        _tab = Dest.queue;
      });

  /// Leave the reading screen, wherever it was entered from. The header label and
  /// the system Back both come here, so they can never disagree about where
  /// "back" is.
  void _leaveArticle() {
    unawaited(_audio.stop());
    _toQueue();
  }

  /// Speak one line from the reading screen. Works with no key at all, because
  /// the device engine is the floor rather than a fallback.
  Future<void> _speakSentence(Article a, int index) async {
    if (index < 0 || index >= a.sentences.length) return;
    // Tapping a line that is already speaking stops it, which is what a second
    // tap on a speaker means everywhere else.
    if (_speakingIndex == index) {
      await _audio.stop();
      if (mounted) setState(() => _speakingIndex = -1);
      return;
    }
    // Same narrator as the Listen screen for the same article — one piece, one
    // voice, whichever screen asked for the sound.
    _audio.narrate(a.id);
    setState(() => _speakingIndex = index);
    await _audio.play(index, a.sentences[index].english);
    if (mounted) setState(() => _speakingIndex = -1);
  }

  /// How many times the OPEN article has been read: today, and in all.
  ///
  /// Read from the database every time the screen opens, because the number is
  /// the receipt — a count that lived only in this session would be gone the
  /// moment the reader left and came back, which is exactly the state that made
  /// them press the button twice.
  int _readsToday = 0;
  int _readsInAll = 0;

  /// A count is in flight. Set SYNCHRONOUSLY before the first await, so a
  /// second tap cannot slip through while the first is being written.
  bool _counting = false;

  Future<void> _loadReadCounts(String articleId) async {
    try {
      final (int today, int total) = await _repo.readCounts(
        articleId: articleId,
        day: todayDay(),
      );
      if (!mounted) return;
      // Guarded against a stale response: the reader can leave one article and
      // open another while this is in flight, and the second one's numbers must
      // not be overwritten by the first one's.
      if (_openId != articleId) return;
      setState(() {
        _readsToday = today;
        _readsInAll = total;
      });
    } catch (e) {
      debugPrint('the read counts could not be read: $e');
    }
  }

  /// Invariant 3: this counts and the article STAYS. Nothing is removed.
  ///
  /// The counts are re-read from the database after the write rather than
  /// incremented here. One source of truth: a number this method added itself
  /// could disagree with the row it just wrote, and the row is what the History
  /// tab and the shelf are built from.
  Future<void> _countRead(Article a) async {
    if (_counting) return;
    setState(() => _counting = true);
    try {
      await _repo.countRead(
        articleId: a.id,
        title: a.title,
        day: todayDay(),
        minutes: a.minuteEstimate,
      );
      await _loadReadCounts(a.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _counting = false);
      Toast.show(context, 'that read could not be counted · $e');
      return;
    }
    if (!mounted) return;
    setState(() => _counting = false);
    // The queue card's counter too. The reader just counted a read on the
    // Article screen; when they go back to the queue that card has to say so, or
    // the count they just paid attention to is invisible where they will look
    // for it next.
    unawaited(_loadQueueCounts());
    // A read counts only when the listener has already heard this one too.
    // Not awaited: the toast is about the READ, and a reader who has just
    // tapped a button should not wait on a queue write to see it land.
    unawaited(_maybeRetireLearned(a.id));
    Toast.show(
      context,
      _readsToday <= 1
          ? 'counted · it stays in your library'
          : 'counted ${_readsToday} times today · it stays in your library',
    );
    // TRIGGER ONE of three: the reader just finished an article. This is the
    // moment the next one should start — not a minute later on a timer, and not
    // at 3am on a background task. If the conditions hold, the planned card
    // begins writing while the reader is still looking at the toast.
    //
    // It is not awaited, and that matters: the write is a 1–3 minute network call
    // and the reader must not wait on it to leave this screen.
    //
    // `_retireAndRefill` above also starts a write when the replacement left
    // nothing unread. Both paths are gated by `_mayAutoWrite`, so calling it
    // twice costs nothing — the second call finds the claim already taken.
    unawaited(_maybeAutoWrite());
  }

  /// The tap that makes this app what it is.
  ///
  /// English first, then one more tap for the translation. A word that is not in
  /// the shipped dictionary is stated plainly — there is no network fallback,
  /// because the promise is that a lookup costs nothing and works in airplane
  /// mode.
  Future<void> _lookupWord(String surface, int sentenceIndex) async {
    final String day = todayDay();

    // Meeting a word IS the mechanic: reading it in an article counts as having
    // met it, and it costs nothing.
    final WordPool? pool = _pool;
    final String key = surface.toLowerCase();
    // Function words are answered but not recorded. They were the bulk of
    // "Your words" — `the`, `and`, `for`, `has` — and a review list padded with
    // them hides the words that actually need another showing. The lookup
    // itself still works; only the history write is skipped.
    final bool worthKeeping = !isStopword(key);
    if (pool != null && worthKeeping) {
      pool.meet(key, day);
      await _repo.meetWord(key, day);
      if (mounted) setState(() {});
    }

    if (!mounted) return;
    final Dictionary? dict = _dict;
    final WordEntry? entry = pool?[key];

    if (dict == null) {
      // Start the load and answer now. The sheet says the dictionary is still
      // loading; the NEXT tap on any word is instant. That is the right trade:
      // the reader asked a question and got an honest answer, instead of
      // watching the app freeze for two seconds mid-sentence.
      unawaited(_dictionaryOnce());
      await showWordSheet(
        context,
        surface: surface,
        entry: const DictEntry(ipa: '', pos: '', en: '', cn: ''),
        miss: LookupMiss.notLoaded,
        starrable: entry != null,
        starCount: entry?.starCount ?? 0,
        starRemaining: entry?.starRemaining ?? 0,
        onStar: () => _starWord(key),
        onUnstar: () => _unstarWord(key),
        onSpeak: () => _speakWord(surface),
        dictionary: dict,
      );
      return;
    }

    final (DictEntry resolved, LookupMiss miss) = dict.resolve(surface);
    if (!mounted) return;

    await showWordSheet(
      context,
      surface: surface,
      entry: resolved,
      miss: miss,
      starrable: entry != null,
      starCount: entry?.starCount ?? 0,
      starRemaining: entry?.starRemaining ?? 0,
      lemma: entry?.lemma != null && entry!.lemma != key ? entry.lemma : null,
      weightFraction: pool == null || entry == null
          ? null
          : selectionChance(entry, pool.all(), day),
      onStar: () => _starWord(key),
      onUnstar: () => _unstarWord(key),
      onSpeak: () => _speakWord(surface),
      dictionary: dict,
    );
  }

  /// Speak a single word, and say so if the phone will not.
  Future<void> _speakWord(String surface) async {
    final bool ok = await _audio.speakWord(surface);
    if (!mounted || ok) return;
    Toast.show(context, 'this phone would not speak · check its voices');
  }

  /// Starring raises the weight IMMEDIATELY and never rewrites an article that
  /// already exists — DESIGN is explicit that a star must not trigger
  /// generation, because that would spend money nobody agreed to spend.
  ///
  /// A star is now ADDITIVE and finite: every tap raises the number of future
  /// articles that must use the word, and once those showings have landed the
  /// word leaves "Crucial now" on its own. That is the difference between a
  /// request the app can keep and a flag that follows the reader forever.
  Future<void> _starWord(String lemma) async {
    final WordPool? pool = _pool;
    final WordEntry? e = pool?[lemma];
    if (e == null) return;
    // The entry is mutated first so the screen answers on this frame; if the
    // write fails, put the old state back rather than leaving the UI claiming
    // a promise the database does not have.
    final bool wasStarred = e.starred;
    final int wasCount = e.starCount;
    final int wasDelivered = e.starDelivered;
    final String? wasDay = e.starredAtDay;
    e.addStar(todayDay());
    try {
      await _repo.saveWordStar(e);
    } catch (err) {
      e.starred = wasStarred;
      e.starCount = wasCount;
      e.starDelivered = wasDelivered;
      e.starredAtDay = wasDay;
      if (!mounted) return;
      setState(() {});
      Toast.show(context, 'that star could not be saved · $err');
      return;
    }
    if (!mounted) return;
    setState(() {});
    final int owed = e.starRemaining;
    Toast.show(
      context,
      owed == 1
          ? 'starred ${e.starCount}× · the next article will use it'
          : 'starred ${e.starCount}× · it is owed $owed more articles',
    );
  }

  /// "Stop asking for this one." Clears the campaign; the next star starts a
  /// new count instead of inheriting one the reader cancelled.
  Future<void> _unstarWord(String lemma) async {
    final WordPool? pool = _pool;
    final WordEntry? e = pool?[lemma];
    if (e == null || !e.starred) return;
    final bool wasStarred = e.starred;
    final int wasCount = e.starCount;
    final int wasDelivered = e.starDelivered;
    final String? wasDay = e.starredAtDay;
    e.clearStar();
    try {
      await _repo.saveWordStar(e);
    } catch (err) {
      e.starred = wasStarred;
      e.starCount = wasCount;
      e.starDelivered = wasDelivered;
      e.starredAtDay = wasDay;
      if (!mounted) return;
      setState(() {});
      Toast.show(context, 'that change could not be saved · $err');
      return;
    }
    if (!mounted) return;
    setState(() {});
    Toast.show(context, 'stopped · it is still in your words, without a star');
  }

  /// The Words screen's star, which passes an explicit intent rather than a tap.
  Future<void> _starWordFromList(String lemma) => _starWord(lemma);
  Future<void> _unstarWordFromList(String lemma) => _unstarWord(lemma);

  // ── library ───────────────────────────────────────────────────────────

  Widget _libraryPage(Queue q) {
    return FutureBuilder<Library>(
      future: _repo.library(q),
      builder: (BuildContext ctx, AsyncSnapshot<Library> snap) {
        if (!snap.hasData) {
          return const Center(child: Text('…'));
        }
        final Library lib = snap.data!;
        return LibraryScreen(
          rows: lib.shelf(),
          usedKb: lib.usedKb,
          freedKb: lib.freedKb,
          goneCount: lib.goneCount,
          onOpen: (ShelfRow r) => _openFromShelf(r, q),
          onFree: (ShelfRow r) => _confirmFree(lib, r),
          onBack: _toQueue,
        );
      },
    );
  }

  /// Open a shelf row. This USED to be a toast that said "opening …" and then
  /// opened nothing, which is the worst of both: the app claims an action it did
  /// not take. A row the reader cannot open is a row that only exists to be
  /// looked at, so it opens — or, if its bytes are gone, says why not.
  ///
  /// THREE places a body can live, and the third one is the one that was
  /// missing. A bundled sample carries its own text; an article written in THIS
  /// session is in `_written`; an article written in an EARLIER session is only
  /// in `article_rows`. `loadArticle` has existed since schema v3 and was never
  /// called by anything, so a paid article the reader archived with
  /// "Done with it" — its slot long since reused — hit the last line and got
  /// "that one is not in the queue right now". The body was on the phone the
  /// whole time. The comment below used to claim the body is "only in memory for
  /// what this session wrote", which stopped being true the moment `landArticle`
  /// started writing it to disk.
  Future<void> _openFromShelf(ShelfRow row, Queue q) async {
    if (row.isGone) {
      Toast.show(context,
          'the text of that one was freed · its ${row.reads}× read count stands');
      return;
    }
    for (final QueueSlot s in q.slots) {
      if (s.articleId == row.articleId && s.article != null) {
        _openArticle(_hydrated(s), fromLibrary: true);
        return;
      }
    }
    // Written this session: still in memory.
    final Article? written = _written[row.articleId];
    if (written != null && written.sentences.isNotEmpty) {
      setState(() {
        _openId = written.id;
        _openFromLibrary = true;
        _listeningOn = false;
        _tab = Dest.article;
      });
      return;
    }
    // Written in an EARLIER session: on disk, and one query away.
    try {
      final Article? stored = await _repo.loadArticle(row.articleId);
      if (!mounted) return;
      if (stored != null && stored.sentences.isNotEmpty) {
        setState(() {
          _openId = stored.id;
          _openFromLibrary = true;
          _listeningOn = false;
          _tab = Dest.article;
        });
        return;
      }
    } catch (e) {
      debugPrint('the stored body of ${row.articleId} could not be read: $e');
      if (!mounted) return;
    }
    Toast.show(context, 'the text of that one is no longer on this phone');
  }

  /// Invariant 4's user-facing half. The sheet states the trade in the reader's
  /// own numbers, and the handler re-checks the guard so a live card can never
  /// be freed even if the UI were wrong.
  Future<void> _confirmFree(Library lib, ShelfRow row) async {
    if (!canFreeSpace(isLiveInQueue: row.isLive, isAlreadyGone: row.isGone)) {
      Toast.show(
        context,
        row.isLive
            ? 'that one is in your queue — Done with it first'
            : 'its space is already freed',
      );
      return;
    }
    if (!mounted) return;
    await AppSheet.show<void>(
      context,
      title: 'Free the space',
      builder: (BuildContext ctx) => FreeSpaceSheet(
        row: row,
        onConfirm: () async {
          Navigator.of(ctx).pop();
          // The row's own articleId, NOT its title. The ledger is keyed by
          // articleId, so passing the title freed nothing at all while the toast
          // cheerfully reported a number.
          await _repo.freeSpace(
            articleId: row.articleId,
            kilobytes: row.kilobytes,
          );
          if (!mounted) return;
          setState(() {});
          Toast.show(context,
              '${formatKb(row.kilobytes)} freed · read ${row.reads}× and heard '
              '${row.listens}× still counted');
        },
      ),
    );
  }

  // ── history ───────────────────────────────────────────────────────────

  Widget _historyPage() {
    final DateTime now = DateTime.now();
    return FutureBuilder<List<({int reads, int listens})>>(
      future: _loadsOfMonth(now.year, now.month),
      builder:
          (BuildContext ctx, AsyncSnapshot<List<({int reads, int listens})>> snap) {
        final List<DayCell> cells = <DayCell>[];
        if (snap.hasData) {
          for (int i = 0; i < snap.data!.length; i++) {
            final ({int reads, int listens}) v = snap.data![i];
            if (v.reads > 0 || v.listens > 0) {
              cells.add(DayCell(day: i + 1, reads: v.reads, listens: v.listens));
            }
          }
        }
        return FutureBuilder<List<({String articleId, String title, int reads, int listens})>>(
          future: _repo.mostRevisited(),
          builder: (BuildContext _, AsyncSnapshot<List<({String articleId, String title, int reads, int listens})>> rs) {
            final List<RevisitedRow> revisited = <RevisitedRow>[
              for (final ({String articleId, String title, int reads, int listens}) r
                  in (rs.data ?? const <({String articleId, String title, int reads, int listens})>[]))
                RevisitedRow(
                  articleId: r.articleId,
                  title: r.title,
                  reads: r.reads,
                  listens: r.listens,
                ),
            ];
            return HistoryScreen(
              year: now.year,
              month: now.month,
              today: now.day,
              cells: cells,
              mostRevisited: revisited,
              onOpenDay: (int day) => _openDay(day, now),
              onOpenArticle: (String id) => _openArticleById(id),
              onBack: _toQueue,
            );
          },
        );
      },
    );
  }

  /// Open an article from a history row. The calendar and *Most revisited*
  /// answer "which one was it"; this is the tap that says "read it again".
  ///
  /// The shelf is asked first, because it is the one index that knows about
  /// every article this phone has ever had — live, written, or freed — and a
  /// freed article has to be told apart from a missing one rather than reported
  /// as the same thing. Failing that, the body is fetched by id directly.
  Future<void> _openArticleById(String articleId) async {
    final Queue? q = _queue;
    if (q != null) {
      final Library lib = await _repo.library(q);
      if (!mounted) return;
      for (final ShelfRow row in lib.shelf()) {
        if (row.articleId == articleId) {
          await _openFromShelf(row, q);
          return;
        }
      }
    }
    // Not on the shelf. It was written in an earlier session and its ledger row
    // is gone, or the id is stale — either way one direct query is the honest
    // attempt before saying the text is not here.
    try {
      final Article? stored = await _repo.loadArticle(articleId);
      if (!mounted) return;
      if (stored != null && stored.sentences.isNotEmpty) {
        setState(() {
          _openId = stored.id;
          _openFromLibrary = true;
          _listeningOn = false;
          _tab = Dest.article;
        });
        return;
      }
    } catch (e) {
      debugPrint('the stored body of $articleId could not be read: $e');
      if (!mounted) return;
    }
    Toast.show(context, 'the text of that one is no longer on this phone');
  }

  /// One day in detail. The screen's own sheet, fed by the SAME day rows the
  /// calendar reads — so the number here cannot disagree with the number there.
  Future<void> _openDay(int day, DateTime month) async {
    final String key = '${month.year}-'
        '${month.month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';

    final List<({String articleId, String title, int reads, int listens})>
        rows = await _repo.dayArticles(key);
    final ({int reads, int listens}) totals = await _repo.dayTotals(key);
    final int minutes = await _repo.dayMinutes(key);

    if (!mounted) return;
    await AppSheet.show<void>(
      context,
      title: '${_monthName(month.month)} $day',
      builder: (BuildContext _) => DaySheet(
        label: '${_monthName(month.month)} $day, ${month.year}',
        reads: totals.reads,
        listens: totals.listens,
        articles: rows,
        minutes: minutes,
        onOpenArticle: (String id) {
          Navigator.of(context).pop();
          unawaited(_openArticleById(id));
        },
      ),
    );
  }

  static String _monthName(int m) => const <String>[
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ][m - 1];

  Future<List<({int reads, int listens})>> _loadsOfMonth(int y, int m) async {
    final int days = DateTime(y, m + 1, 0).day;
    final List<({int reads, int listens})> out =
        <({int reads, int listens})>[];
    for (int d = 1; d <= days; d++) {
      final int day = int.parse('$d');
      final String key =
          '$y-${m.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      out.add(await _repo.dayTotals(key));
    }
    return out;
  }

  // ── words ─────────────────────────────────────────────────────────────

  Widget _wordsPage() {
    final WordPool? pool = _pool;
    if (pool == null) return const Center(child: Text('…'));
    final String day = todayDay();
    // `pool.all()` used to be called TWICE PER ROW — once for the row and
    // again inside `selectionChance`, each call re-sorting the whole pool. On a
    // few hundred words that is hundreds of thousands of comparisons per
    // frame. The list and its total weight are computed once, and both sections
    // are built from them.
    final List<WordEntry> entries = pool.all();
    final double totalWeight = entries.fold<double>(
      0.0,
      (double sum, WordEntry e) => sum + e.weightAsOf(day),
    );
    double fractionOf(WordEntry e) =>
        totalWeight <= 0 ? 0 : e.weightAsOf(day) / totalWeight;

    final List<WordRow> crucial = pool
        .crucial(day)
        .map((WordEntry e) => WordRow(
              lemma: e.lemma,
              encounters: e.encounters,
              starred: e.starred,
              starCount: e.starCount,
              starRemaining: e.starRemaining,
              fraction: fractionOf(e),
            ))
        .toList();
    final List<WordRow> all = entries
        .map((WordEntry e) => WordRow(
              lemma: e.lemma,
              encounters: e.encounters,
              starred: e.starred,
              starCount: e.starCount,
              starRemaining: e.starRemaining,
              fraction: fractionOf(e),
            ))
        .toList();

    return WordsScreen(
      crucial: crucial,
      all: all,
      onStar: _starWordFromList,
      onUnstar: _unstarWordFromList,
      onOpen: (String lemma) => _openWord(lemma),
      // Words is a bottom-bar tab, not a pushed screen, so this calls the tab
      // switcher rather than `_pop`. It was left null, and the header rendered
      // a label that looked like every other header button and did nothing.
      onBack: _toQueue,
    );
  }

  Future<void> _openWord(String lemma) async {
    if (_dict == null) unawaited(_dictionaryOnce());
    final Dictionary? dict = _dict;
    if (dict == null || !mounted) {
      if (mounted) Toast.show(context, 'the dictionary is still loading');
      return;
    }
    final (DictEntry e, LookupMiss miss) = dict.resolve(lemma);
    if (!mounted) return;
    await showWordSheet(
      context,
      surface: lemma,
      entry: e,
      miss: miss,
      starrable: _pool?[lemma] != null,
      starCount: _pool?[lemma]?.starCount ?? 0,
      starRemaining: _pool?[lemma]?.starRemaining ?? 0,
      onStar: () => _starWord(lemma),
      onUnstar: () => _unstarWord(lemma),
      onSpeak: () => _speakWord(lemma),
      dictionary: dict,
    );
  }

  // ── settings ──────────────────────────────────────────────────────────

  /// [pane] lets a caller open straight onto a page. The queue's "See all saved
  /// instructions" link uses it, because a reader who tapped that link asked for
  /// the manager and would rather not be shown the hub and made to find it.
  Widget _settings({Pane pane = Pane.hub}) {
    // Re-read the counter on the way in. The row is the only place the reader
    // can see how much of the month is left, and a number that is only correct
    // at boot is a number that is wrong for most of the time it is on screen.
    unawaited(_loadAutoWriteUsed());
    return SettingsScreen(
      initialPane: pane,
      model: SettingsModel(
        plan: _plan,
        writerId: _writerId,
        writerBase: _writerBase,
        writerModel: _writerModel,
        writerKeySaved: _hasWriterKey,
        voiceSource: _voiceSourceId,
        voiceBase: _voiceBase,
        voiceName: _voiceName,
        voiceModel: _voiceModel,
        voiceKeySaved: _hasVoiceKey,
        deviceVoice: _audio.deviceVoice,
        appearance: _appearance,
        face: _face,
        listenAutoPlay: _listenAutoPlay,
        listenAutoContinue: _listenAutoContinue,
        listenAutoContinueCount: _listenAutoContinueCount,
        listenAutoOrder: _listenAutoOrder,
        dictionaryEntries: _dict?.size ?? 0,
        newsKeySaved: _hasNewsKey,
        newsOn: _newsOn,
        searchKeySaved: _hasSearchKey,
        searchOn: _searchOn,
        autoWrite: _autoWrite,
        autoWriteUsed: _autoWriteUsed,
        autoWriteCeiling: kAutoWriteMonthlyCeiling,
        version: _version,
        build: _buildNumber,
      ),
      onBack: _pop,
      onPlanChanged: _savePlan,
      // Null without a key, so the button is disabled rather than failing at
      // the network. A control that is offered and then refuses is worse than
      // one that says up front that it cannot be used yet.
      onRewritePlan: _hasWriterKey ? _rewritePlan : null,
      // Both go up to the app root, which owns the theme, and it is the root
      // that writes them down — one place saves a preference, so there is one
      // place for it to be saved wrong.
      onAppearance: (AppearanceMode a) {
        setState(() => _appearance = a);
        widget.onAppearance(a);
      },
      onFace: (ReadingFace f) {
        setState(() => _face = f);
        widget.onFace(f);
      },
      onWriterSelected: (String id) {
        final WriterEndpoint ep = WriterEndpoint.byId(id);
        // Tapping the provider that is ALREADY selected is not a switch, and
        // it must not wipe the reader's custom base URL or model id. Only a
        // real change resets the two values that belong to the old provider —
        // a model id from DeepSeek sent to OpenAI can only be refused.
        final bool changed = ep.id != _writerId;
        setState(() {
          _writerId = ep.id;
          if (changed) {
            _writerBase = ep.baseUrl;
            _writerModel = '';
          }
        });
        unawaited(_save('writer:id', ep.id));
        if (changed) {
          unawaited(_save('writer:base', ep.baseUrl));
          unawaited(_save('writer:model', ''));
        }
      },
      onWriterBaseChanged: (String base) {
        setState(() => _writerBase = base);
        unawaited(_save('writer:base', base));
      },
      onWriterModelChanged: (String model) {
        setState(() => _writerModel = model);
        unawaited(_save('writer:model', model));
      },
      onWriterKeyChanged: (String key) async {
        await _keys.saveWriter(key);
        if (!mounted) return;
        // The hub row and the Test button both read this flag. Not setting it is
        // why a saved key still showed as "not set" and Test stayed disabled:
        // the reader saved a key and the screen said they had not.
        setState(() => _hasWriterKey = key.trim().isNotEmpty);
        Toast.show(context, 'saved on this phone');
      },
      onVoiceSelected: (String source) {
        setState(() => _voiceSourceId = source);
        unawaited(_save('voice:source', source));
        unawaited(_applyVoice());
      },
      onVoiceBaseChanged: (String base) {
        setState(() => _voiceBase = base);
        unawaited(_save('voice:base', base));
        unawaited(_applyVoice());
      },
      onVoiceNameChanged: (String name) {
        setState(() => _voiceName = name);
        unawaited(_save('voice:name', name));
        unawaited(_applyVoice());
      },
      onVoiceModelChanged: (String model) {
        setState(() => _voiceModel = model);
        unawaited(_save('voice:model', model));
        unawaited(_applyVoice());
      },
      onVoiceKeyChanged: (String key) async {
        await _keys.saveVoice(key);
        if (!mounted) return;
        // A saved key with MiMo not selected is still a configuration the reader
        // made, so honour it rather than waiting for a second tap.
        setState(() => _voiceSourceId = 'mimo');
        await _save('voice:source', 'mimo');
        await _applyVoice();
        if (!mounted) return;
        Toast.show(context, 'saved on this phone · MiMo is now the voice');
      },

      // ── listening ──────────────────────────────────────────────────
      onListenAutoPlay: (bool on) {
        setState(() => _listenAutoPlay = on);
        unawaited(_save('listen:autoPlay', on ? 'on' : 'off'));
      },
      onListenAutoOrder: (String order) {
        setState(() => _listenOrder = ListenOrder.fromKey(order));
        unawaited(_save('listen:autoOrder', order));
      },
      onProbeVoice: () async {
        await _applyVoice();
        return _audio.probeMiMo();
      },
      onTestWriter: () async {
        final String? key = await _keys.writer();
        if (key == null) return 'No key is saved, so nothing was sent.';
        try {
          await _api.testWriter(
            endpoint: _writerEndpoint,
            apiKey: key,
          );
          return null;
        } on RemoteFailure catch (e) {
          return e.message + e.cost;
        } catch (e) {
          return '$e';
        }
      },

      // ── instructions ────────────────────────────────────────────────
      onLoadInstructions: () => _repo.instructions(),
      onSaveInstruction: _saveInstruction,
      onDeleteInstruction: _deleteInstruction,

      // ── the two optional sources ────────────────────────────────────
      onNewsKeyChanged: (String key) async {
        await _keys.saveNews(key);
        if (!mounted) return;
        setState(() {
          _hasNewsKey = key.trim().isNotEmpty;
          _newsOn = _hasNewsKey;
        });
        await _save('news:on', _newsOn ? 'on' : 'off');
        if (!mounted) return;
        Toast.show(context, 'saved on this phone · the news source is on');
      },
      onNewsToggled: (bool on) async {
        setState(() => _newsOn = on);
        await _save('news:on', on ? 'on' : 'off');
      },
      onTestNews: _testNews,

      onSearchKeyChanged: (String key) async {
        await _keys.saveSearch(key);
        if (!mounted) return;
        setState(() {
          _hasSearchKey = key.trim().isNotEmpty;
          _searchOn = _hasSearchKey;
        });
        await _save('search:on', _searchOn ? 'on' : 'off');
        if (!mounted) return;
        Toast.show(context, 'saved on this phone · web search is on');
      },
      onSearchToggled: (bool on) async {
        setState(() => _searchOn = on);
        await _save('search:on', on ? 'on' : 'off');
      },
      onTestSearch: _testSearch,
      onAutoWriteChanged: (bool on) {
        setState(() => _autoWrite = on);
        unawaited(_save('auto:write', on ? 'on' : 'off'));
        // Turning it ON is worth acting on immediately. A reader who has just
        // turned this on is looking at a queue with a planned card in it, and
        // the moment they flip the switch is the moment they want it to start —
        // not the next time they happen to finish an article.
        //
        // And if the month is already full, `_maybeAutoWrite` will say so
        // through `_sayCeilingReachedOnce`. That is the difference between a
        // switch that does nothing and a switch that explains itself: flipping
        // it on into a full month used to be completely silent, and the reader
        // had no way to tell a disabled feature from a broken one.
        if (on) unawaited(_maybeAutoWrite());
      },

      onOpenDebugLog: () => _push(() => DebugLogScreen(onBack: _pop)),
    );
  }

  // ── instructions ──────────────────────────────────────────────────────

  /// Save a new instruction, or overwrite one. Returns a sentence on failure.
  ///
  /// A duplicate is allowed rather than refused. Two instructions that read the
  /// same are the reader's business — deduplicating them silently would throw
  /// away a row they can see, and a list that edits itself is worse than one
  /// with a redundant line in it.
  Future<String?> _saveInstruction(String text, {String? id}) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return 'An instruction has to say something.';
    try {
      await _repo.upsertInstruction(
        Instruction(
          id: id ?? 'ins-${DateTime.now().microsecondsSinceEpoch}',
          text: trimmed,
          createdDay: todayDay(),
        ),
      );
      return null;
    } catch (e) {
      return 'That could not be saved · $e';
    }
  }

  Future<String?> _deleteInstruction(String id) async {
    try {
      await _repo.deleteInstruction(id);
      return null;
    } catch (e) {
      return 'That could not be deleted · $e';
    }
  }

  // ── the two optional source tests ─────────────────────────────────────
  //
  // Both are ONE request that proves the key works and writes nothing. The
  // news test fetches the list (free, 358 ms measured); the search test runs
  // `tools/list` against the MCP, which answers with the tool names and costs
  // no model call at all.

  Future<String?> _testNews() async {
    final String? key = await _keys.news();
    if (key == null || key.trim().isEmpty) {
      return 'No key is saved, so nothing was sent.';
    }
    final NewsSource source = NewsSource();
    try {
      final List<NewsItem> items = await source.hotboard(apiKey: key);
      if (items.isEmpty) {
        return 'The news source answered, but with no stories in it.';
      }
      return '${items.length} stories came back. Nothing was written.';
    } catch (e) {
      return 'The news source could not be reached · $e';
    } finally {
      source.close();
    }
  }

  Future<String?> _testSearch() async {
    final String? key = await _keys.search();
    if (key == null || key.trim().isEmpty) {
      return 'No key is saved, so nothing was sent.';
    }
    try {
      final List<String> tools = await McpClient.listTools(apiKey: key);
      if (tools.isEmpty) {
        return 'The search service answered, but offers no tools.';
      }
      return 'It offers ${tools.join(', ')}. Nothing was written.';
    } catch (e) {
      return 'The search service could not be reached · $e';
    }
  }

  /// What Android says is installed. Empty until the read lands — the hub says
  /// "reading it…" rather than showing a number it does not have.
  ///
  /// This is the only reason `package_info_plus` is a dependency: the question
  /// "is the phone running the APK I just built?" cannot be answered from
  /// inside the Dart source, because the source is the same for both builds.
  String _version = '';
  String _buildNumber = '';

  Future<void> _loadVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    } catch (e) {
      // A version that cannot be read is not a reason to fail a launch.
      debugPrint('the version could not be read: $e');
    }
  }

  bool _hasWriterKey = false;
  bool _hasVoiceKey = false;

  // The two optional sources. `_has*Key` is what the keystore says; `_*On` is
  // what the reader wants. Both are needed: a saved-but-switched-off source
  // must stay off across a restart, and a switched-on source with no key must
  // not be consulted.
  bool _hasNewsKey = false;
  bool _hasSearchKey = false;
  bool _newsOn = false;
  bool _searchOn = false;

  /// True when the writer may reach the network for research. This is the one
  /// test that decides whether a write takes the agent path or the single-call
  /// path — and it is what keeps "one call" an honest thing to print on a card
  /// for a reader who has configured nothing.
  bool get _canResearch => _hasWriterKey && (_newsOn || _searchOn);

  /// Re-point the player after any voice change. One place, so the engine in
  /// play can never disagree with the row that claims to be selected.
  ///
  /// The article in flight keeps its narrator. `configure` deliberately does not
  /// re-roll the voice while something is playing — a settings change used to
  /// swap the MiMo voice for the rest of the article, which is a voice change
  /// in the middle of a piece from a screen that has nothing to do with
  /// playback. The next `narrate` applies the new setting.
  Future<void> _applyVoice() async {
    final String? key = await _keys.voice();
    _hasVoiceKey = key != null && key.trim().isNotEmpty;
    _audio.configure(
      source: _voiceSourceId == 'mimo' && _hasVoiceKey
          ? VoiceSource.recorded
          : VoiceSource.device,
      apiKey: key ?? '',
      baseUrl: _voiceBase,
      voice: _voiceName,
      model: _voiceModel,
    );
    if (mounted) setState(() {});
  }

  /// The sentence under the transport that says who is speaking.
  ///
  /// THREE STATES, and naming them is the point:
  ///
  ///  · this article is being narrated by a MiMo recording → the voice id, so
  ///    "which one is this?" has an answer;
  ///  · the recording failed and the phone took over → the device voice's own
  ///    name, so a reader who hears the narrator change is told rather than
  ///    left wondering whether they imagined it;
  ///  · the phone is the only engine → the same, plainly.
  ///
  /// The old label said "a recorded voice · MiMo · online · free" whether or
  /// not a recording was actually playing, which is exactly the sentence that
  /// makes a reader distrust every other sentence on the screen.
  String _voiceLabel() {
    final bool recording = _audio.narrator == Narrator.recorded;
    if (recording) {
      final String id = _audio.speakingAs;
      return id.isEmpty ? 'a recorded voice · MiMo' : '$id · MiMo · recorded';
    }
    final String name = _audio.deviceVoice.name;
    if (name.isNotEmpty) return '$name · this phone';
    return "the phone's own voice · free · offline";
  }
}

/// The notice that states the app's one real promise.
///
/// It used to say "tap 译 on a sentence for 中文", which put the whole
/// interaction in a language the reader is still learning. Everything in this app
/// is English except the translations themselves; the notice is no exception.
///
/// It is a FOOTNOTE, not a card. A rounded surface with a border and a bold
/// title looks like one of the three article cards above it, and a reader who
/// taps a thing that does nothing concludes the app is broken. The promise is
/// one line of text under the queue, the way any other aside sits.
class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    // One line. It used to explain the whole interaction model — tap a word,
    // hold a line, the Listen tab plays the whole thing, nothing to confirm —
    // which is a manual, and a manual that is always on screen is a manual
    // nobody reads past the second day.
    return Text(
      'Every word and every sentence has sound.',
      style: TextStyle(
        fontFamily: TypeScale.sans,
        fontSize: 12,
        color: c.ink3,
      ),
    );
  }
}