// Marginalia — three articles are always waiting.
//
// No-Stop English: an offline-first English reader. Five screens, two verbs, and
// a queue of three. No schedule, no streak, and nothing anywhere asks whether you
// remember a word.
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
import 'domain/plan.dart';
import 'domain/queue.dart';
import 'domain/word_pool.dart';
import 'features/article/article_screen.dart';
import 'features/article/listen_screen.dart';
import 'features/article/word_sheet.dart';
import 'features/history/history_screen.dart';
import 'features/library/library_screen.dart';
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

class _ShellState extends State<_Shell> {
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
  /// `newest` · `oldest` · `mostStudied` · `leastStudied` · `random`.
  String _listenAutoOrder = 'newest';

  /// Mirrors of the two preferences the app root owns. Held here too because
  /// this is where the Settings screen is built from, and because this is the
  /// object that can reach the database to save them.
  AppearanceMode _appearance = AppearanceMode.system;
  ReadingFace _face = ReadingFace.notoSerif;

  // ── the two keys and where they point ─────────────────────────────────
  String _writerId = 'deepseek';
  String _writerBase = WriterEndpoint.deepseek.baseUrl;
  String _voiceBase = VoiceEndpoint.mimo.baseUrl;
  String _voiceName = VoiceEndpoint.mimo.voices.first;
  String _voiceSourceId = 'device';

  @override
  void initState() {
    super.initState();
    _boot();
    // Deliberately NOT awaited and not part of `_boot`. Reading the version
    // touches the platform channel, and the boot sequence is ordered on purpose
    // — a version string is not worth a place in it. It lands whenever it lands
    // and the hub row fills itself in.
    unawaited(_loadVersion());
  }

  @override
  void dispose() {
    _db.close();
    _audio.dispose();
    _api.close();
    super.dispose();
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
    final String? vbase = await get('voice:base');
    final String? vname = await get('voice:name');
    final String? vsrc = await get('voice:source');
    // Listen behaviour. Absent means OFF / no-continue / newest — the quiet
    // defaults, so a reader who has never opened Settings is never surprised.
    final String? lauto = await get('listen:autoPlay');
    final String? lcont = await get('listen:autoContinue');
    final String? lcontN = await get('listen:autoContinueCount');
    final String? lorder = await get('listen:autoOrder');
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
      _listenAutoOrder = <String>{
        'newest',
        'oldest',
        'mostStudied',
        'leastStudied',
        'random',
      }.contains(lorder)
          ? lorder!
          : 'newest';
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
      _voiceBase = vbase ?? VoiceEndpoint.mimo.baseUrl;
      _voiceName = vname ?? VoiceEndpoint.mimo.voices.first;
      _voiceSourceId = vsrc ?? (hasVoice ? 'mimo' : 'device');

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
      endpoint: WriterEndpoint.byId(_writerId),
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
  QueueSlot _freePlan() {
    _planCounter++;
    final LengthBand band = _randomBand();
    return QueueSlot(
      articleId: 'plan-${DateTime.now().millisecondsSinceEpoch}-$_planCounter',
      state: SlotState.planned,
      plannedWords: _plan.wordsFor(band),
      plannedBand: band,
    );
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
      child: _stack.isNotEmpty ? _stack.last() : _root(),
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
        const SizedBox(height: 4),
        Text(
          'Finish one and the next is written at once. Read in any order, or '
          'just listen.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.6,
            color: context.colors.ink3,
          ),
        ),
        const SizedBox(height: 18),
        // The prototype's order: the cards, then the notice, then the aside.
        // The notice comes AFTER the list because it is a footnote about sound,
        // not an introduction to the queue.
        for (int i = 0; i < q.slots.length; i++)
          QueueCard(
            slot: _hydrated(q.slots[i]),
            onOpen: () => _openArticle(q.slots[i]),
            onMenu: () => _slotMenu(context, q, i),
            onWrite: () => _write(q, i),
            onReroll: () => _reroll(q, i),
            // Read off the LIVE slot, not the hydrated copy. `_hydrated` returns
            // a value object for rendering; the flag that says a call is in
            // flight belongs to the slot the call is writing into.
            writing: q.slots[i].isWriting,
            // The card's price depends on whether a source is configured, so
            // the card is told rather than left to assume. A reader with no
            // optional keys still sees `Write it · ~$0.002`.
            research: _canResearch,
            // A bundled sample is not a generated article. Saying so on the
            // card is the difference between "the writer keeps producing the
            // same thing" and "this one shipped with the app".
            isSample: _samples.containsKey(q.slots[i].articleId),
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
                  ? 'planned · not written yet · nothing has been paid for'
                  : (slot.article?.sentences.isEmpty ?? true)
                      ? 'written, but the text is no longer on this phone'
                      : '${slot.article?.wordCount ?? 0} words · '
                          '${slot.article?.minuteEstimate ?? 0} min read',
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
              _menuRow('Change it', 'what it is about, and how long · free',
                  () async {
                Navigator.of(ctx).pop();
                await _changeIt(q, index);
              }),
              _menuRow('Draw another plan', 'free · no input needed', () async {
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
              _menuRow('Write a new one',
                  'choose the subject · the old one is kept', () async {
                Navigator.of(ctx).pop();
                await _writeAgain(q, index);
              }),
              _menuRow('Done with it',
                  'shelve it — this is not a read', () async {
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
    Toast.show(context,
        '${retired.title} is in your library · not counted as a read');
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

    q.editPlan(
      index,
      instruction: req.instruction,
      instructionId: req.instructionId,
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
    // Ask FIRST, before anything is retired or paid for. The old article is
    // still on screen while the sheet is open, and a reader who backs out has
    // changed nothing and spent nothing — which is what cancel has to mean.
    final List<Instruction> saved =
        await _repo.instructions(limit: kRecentInstructions);
    if (!mounted) return;
    final PlanRequest? req = await AppSheet.show<PlanRequest>(
      context,
      builder: (BuildContext ctx) => RegenerateSheet(
        initialInstruction: '',
        initialInstructionId: null,
        initialBand: LengthBand.medium,
        initialWords: 0,
        plan: _plan,
        instructions: saved,
        onSeeAll: () => _push(() => _settings(pane: Pane.instructions)),
      ),
    );
    if (req == null || !mounted) return;

    final Article? retired = q.retireReadySlot(index, _freePlan());
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

  /// THE ONLY PATH THAT COSTS MONEY, and it is a tap.
  Future<void> _write(Queue q, int index) async {
    QueueSlot slot = q.slots[index];
    if (!slot.isPlanned) {
      Toast.show(context, 'that one is already written');
      return;
    }
    // The guard that costs money if it is missing.
    //
    // A slot stays `planned` for the whole write, so the check above does NOT
    // stop a second tap — and a second tap is a second paid request, for an
    // article that overwrites the first. The button is disabled while busy, but
    // a disabled button is a UI fact and this is the one place that has to be a
    // fact about the code.
    if (slot.isWriting) return;

    // Never write a paid article under a bundled sample's id.
    //
    // Older builds kept a slot's id when a ready card was retired, so a sample
    // slot could be reused for real writes. The write then landed under
    // `a-sample-pointers` and every lookup preferred the bundle, so the reader
    // paid for an article they could never open. Mint a fresh id instead of
    // producing another shadowed write.
    if (_samples.containsKey(slot.articleId)) {
      q.reidentify(index, _freePlan().articleId);
      await _repo.saveQueue(q);
      slot = q.slots[index];
    }

    final String? key = await _keys.writer();
    if (key == null || key.trim().isEmpty) {
      Toast.show(context, 'no writer key is saved — nothing was spent');
      _push(_settings);
      return;
    }

    final WriterEndpoint ep = WriterEndpoint.byId(_writerId);
    // The card shows it is working, so a tap cannot become a second call while
    // the first is still in flight.
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
    final AgentLoop? agent = await _buildAgent(ep, key);
    final List<NewsItem> news = _newsForThisWrite;
    final List<String> recent = await _recentTitles();
    final List<String> met = <String>[
      for (final WordEntry w in _pool?.crucial(todayDay()) ?? const <WordEntry>[])
        w.lemma,
    ];
    if (!mounted) return;

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
    if (slot.instructionId != null) {
      unawaited(_repo.touchInstruction(slot.instructionId!, todayDay()));
    }

    // The article exists from here on. A failure below is a STORAGE failure.
    _written[article.id] = article;
    q.writeSlot(index, article);
    try {
      // The body goes to the database BEFORE the queue says `ready`. A card
      // that says ready while the body is only in memory is a card that opens
      // nothing after a restart — which is exactly the bug this fixes.
      final int bytes = await _repo.saveArticle(article);
      await _repo.saveQueue(q);
      await _repo.recordLedger(
        articleId: article.id,
        title: article.title,
        keywords: article.keywords,
        day: todayDay(),
        // Ceiling, not floor: an article smaller than a kilobyte still costs a
        // kilobyte of the budget, and a bar that says "0 KB" next to an article
        // the reader can see is a bar nobody believes again.
        kilobytes: (bytes / 1024).ceil().clamp(1, 1 << 20),
      );
    } catch (e) {
      debugPrint('the article could not be saved: $e');
      if (!mounted) return;
      setState(() {});
      Toast.show(
        context,
        '${article.title} is here, but could not be saved to this phone · $e',
        duration: const Duration(seconds: 6),
      );
      return;
    }

    if (!mounted) return;
    setState(() {});
    // The call count is the REAL one, out of the loop. It used to say "one
    // call" unconditionally, which was true while the writer was a single
    // request and stopped being true the moment research was configured. A
    // price on screen has to be the price that was charged.
    final int calls = ran?.modelCalls ?? 1;
    final String callLine = calls == 1 ? 'one call' : '$calls calls';
    Toast.show(context,
        '${article.title} is ready · ~${article.wordCount} words · $callLine');
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
    return AgentLoop(endpoint: ep, apiKey: writerKey, tools: tools);
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
    q.reroll(index, _freePlan());
    _repo.saveQueue(q);
    setState(() {});
    Toast.show(context, 'a different plan · nothing was paid for');
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
      voiceLabel: _audio.source.label,
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
      onNextArticle: _peekNextListen() != null ? _playNextArticle : null,
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
  Future<void> _countListen(Article a) async {
    await _repo.countListen(
      articleId: a.id,
      title: a.title,
      day: todayDay(),
    );
    if (!mounted) return;
    Toast.show(context, 'counted a listen. reads untouched.');
    setState(() {});
    unawaited(_loadListenCounts(a.id));
  }

  /// One completed play-through. Counting lives HERE rather than on Play,
  /// because the rule is "a full listen counts, a start does not". An
  /// interrupted pass never reaches `onFinished`, so it is never counted.
  ///
  /// `loop` never reaches here at all — the player wraps and keeps speaking —
  /// but the guard is kept so a future caller cannot accidentally fall into
  /// auto-continue while the reader asked for one article on repeat.
  Future<void> _onListenFinished(Article a) async {
    await _countListen(a);
    if (!mounted) return;
    if (_listenAutoContinue == 'off' || _listenAutoContinue == 'loop') return;
    if (_listenAutoContinue == 'count') {
      if (_autoContinueLeft <= 0) return;
      _autoContinueLeft--;
    }
    await _playNextArticle();
  }

  /// Remaining auto-continues this session when the mode is `count`.
  int _autoContinueLeft = 0;

  int _listensInAll = 0;

  final Map<String, int> _studyCounts = <String, int>{};
  final Map<String, String> _lastSeen = <String, String>{};

  /// Reads + listens, the same "how much have I met this" number the shelf uses.
  int _studyOf(String articleId) => _studyCounts[articleId] ?? 0;
  String _lastSeenOf(String articleId) => _lastSeen[articleId] ?? '';

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
        _studyCounts[articleId] = total + listens;
        _lastSeen[articleId] = todayDay();
      });
    } catch (e) {
      debugPrint('listen counts unavailable: $e');
    }
  }

  /// Advance to the next article and start it. Silent when there is nothing.
  Future<void> _playNextArticle() async {
    final String? nextId = _peekNextListen();
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

  /// The next article to listen to, or null. Sees the live queue.
  ///
  /// Ordering is the reader's setting: a commute that always plays the same
  /// three in the same order gets old, and "heard it today" is the one fact
  /// that should push a random pick away from something.
  String? _peekNextListen() {
    final List<({String id, int studied, String seen})> all =
        <({String id, int studied, String seen})>[];
    final Set<String> ids = <String>{};
    for (final QueueSlot s in _queue?.slots ?? const <QueueSlot>[]) {
      final Article? a = _articleFor(s.articleId);
      if (a == null || a.sentences.isEmpty) continue;
      if (!ids.add(a.id)) continue;
      all.add((id: a.id, studied: _studyOf(a.id), seen: _lastSeenOf(a.id)));
    }
    final String? current = _openId;
    final List<({String id, int studied, String seen})> others =
        <({String id, int studied, String seen})>[
      for (final e in all)
        if (e.id != current) e,
    ];
    if (others.isEmpty) return null;

    switch (_listenAutoOrder) {
      case 'oldest':
        others.sort((a, b) => a.id.compareTo(b.id));
      case 'mostStudied':
        others.sort((a, b) => b.studied.compareTo(a.studied));
      case 'leastStudied':
        others.sort((a, b) => a.studied.compareTo(b.studied));
      case 'random':
        final List<({String id, int studied, String seen})> fresh =
            <({String id, int studied, String seen})>[
          for (final e in others)
            if (e.seen != todayDay()) e,
        ];
        final List<({String id, int studied, String seen})> pool =
            fresh.isNotEmpty ? fresh : others;
        return pool[Random().nextInt(pool.length)].id;
      case 'newest':
      default:
        // `_freePlan` ids are `plan-<millis>-…`, so a descending sort is a
        // descending creation order. The bundled sample has a stable id.
        others.sort((a, b) => b.id.compareTo(a.id));
    }
    return others.first.id;
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
    Toast.show(
      context,
      _readsToday <= 1
          ? 'counted · it stays in your queue'
          : 'counted ${_readsToday} times today · it stays in your queue',
    );
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
    if (pool != null) {
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
        starred: entry?.starred ?? false,
        onToggleStar: (bool next) => _setStarred(key, next, day),
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
      starred: entry?.starred ?? false,
      lemma: entry?.lemma != null && entry!.lemma != key ? entry.lemma : null,
      weightFraction: pool == null || entry == null
          ? null
          : selectionChance(entry, pool.all(), day),
      onToggleStar: (bool next) => _setStarred(key, next, day),
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
  /// The sheet flips its own state on the tap; this is the write behind it, and
  /// it takes the reader's intended value rather than flipping again. Two
  /// independent inversions of the same boolean is how a control ends up doing
  /// nothing when tapped twice.
  Future<void> _setStarred(String lemma, bool next, String day) async {
    final WordPool? pool = _pool;
    final WordEntry? e = pool?[lemma];
    if (e == null) return;
    if (e.starred == next) return;
    e.setStarred(next, day);
    await _repo.setStarred(lemma, next, day);
    if (!mounted) return;
    setState(() {});
    Toast.show(
      context,
      next
          ? 'starred · it comes round again sooner, and nothing is rewritten'
          : 'removed from the front of the pool',
    );
  }

  /// The Words screen's star, which passes an explicit intent rather than a tap.
  Future<void> _setStarredFromList(String lemma, bool next) =>
      _setStarred(lemma, next, todayDay());

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
  void _openFromShelf(ShelfRow row, Queue q) {
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
    // In the ledger but no longer in the queue: the body is only in memory for
    // what this session wrote, so say the fact rather than opening an empty page.
    final Article? written = _written[row.articleId];
    if (written != null) {
      setState(() {
        _openId = written.id;
        _openFromLibrary = true;
        _listeningOn = false;
        _tab = Dest.article;
      });
      return;
    }
    Toast.show(context, 'that one is not in the queue right now');
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
        return FutureBuilder<List<({String title, int reads, int listens})>>(
          future: _repo.mostRevisited(),
          builder: (BuildContext _, AsyncSnapshot<List<({String title, int reads, int listens})>> rs) {
            final List<RevisitedRow> revisited = <RevisitedRow>[
              for (final ({String title, int reads, int listens}) r
                  in (rs.data ?? const <({String title, int reads, int listens})>[]))
                RevisitedRow(title: r.title, reads: r.reads, listens: r.listens),
            ];
            return HistoryScreen(
              year: now.year,
              month: now.month,
              today: now.day,
              cells: cells,
              mostRevisited: revisited,
              onOpenDay: (int day) => _openDay(day, now),
              onBack: _toQueue,
            );
          },
        );
      },
    );
  }

  /// One day in detail. The screen's own sheet, fed by the SAME day rows the
  /// calendar reads — so the number here cannot disagree with the number there.
  Future<void> _openDay(int day, DateTime month) async {
    final String key = '${month.year}-'
        '${month.month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';

    final List<({String title, int reads, int listens})> rows =
        await _repo.dayArticles(key);
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
    final List<WordRow> crucial = pool
        .crucial(day)
        .map((WordEntry e) => WordRow(
              lemma: e.lemma,
              encounters: e.encounters,
              starred: e.starred,
              fraction: selectionChance(e, pool.all(), day),
            ))
        .toList();
    final List<WordRow> all = pool
        .all()
        .map((WordEntry e) => WordRow(
              lemma: e.lemma,
              encounters: e.encounters,
              starred: e.starred,
              fraction: selectionChance(e, pool.all(), day),
            ))
        .toList();

    return WordsScreen(
      crucial: crucial,
      all: all,
      onStar: _setStarredFromList,
      onOpen: (String lemma) => _openWord(lemma),
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
      starred: _pool?[lemma]?.starred ?? false,
      onToggleStar: (bool next) => _setStarred(lemma, next, todayDay()),
      onSpeak: () => _speakWord(lemma),
      dictionary: dict,
    );
  }

  // ── settings ──────────────────────────────────────────────────────────

  /// [pane] lets a caller open straight onto a page. The queue's "See all saved
  /// instructions" link uses it, because a reader who tapped that link asked for
  /// the manager and would rather not be shown the hub and made to find it.
  Widget _settings({Pane pane = Pane.hub}) {
    return SettingsScreen(
      initialPane: pane,
      model: SettingsModel(
        plan: _plan,
        writerId: _writerId,
        writerBase: _writerBase,
        writerKeySaved: _hasWriterKey,
        voiceSource: _voiceSourceId,
        voiceBase: _voiceBase,
        voiceName: _voiceName,
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
        setState(() {
          _writerId = ep.id;
          _writerBase = ep.baseUrl;
        });
        unawaited(_save('writer:id', ep.id));
        unawaited(_save('writer:base', ep.baseUrl));
      },
      onWriterBaseChanged: (String base) {
        setState(() => _writerBase = base);
        unawaited(_save('writer:base', base));
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
        setState(() => _listenAutoOrder = order);
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
            endpoint: WriterEndpoint.byId(_writerId),
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
    );
    if (mounted) setState(() {});
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Every word and every sentence has sound',
          style: TextStyle(
            fontFamily: TypeScale.sans,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: c.ink2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'tap a word for its meaning · hold a line to hear it · the Listen '
          'tab plays the whole thing · nothing to confirm — the app records '
          'what you touched and never asks whether you remember',
          style: TextStyle(
            fontFamily: TypeScale.sans,
            fontSize: 12,
            height: 1.55,
            color: c.ink3,
          ),
        ),
      ],
    );
  }
}