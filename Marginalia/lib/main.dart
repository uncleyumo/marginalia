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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show SystemChrome, SystemNavigator, SystemUiOverlayStyle;

import 'app/bottom_bar.dart';
import 'core/design/tokens.dart';
import 'core/widgets/primitives.dart';
import 'core/widgets/texture.dart';
import 'data/audio.dart';
import 'data/database.dart' hide WordRow;
import 'data/dictionary.dart';
import 'data/keystore.dart';
import 'data/remote/api.dart';
import 'data/repository.dart';
import 'data/samples.dart';
import 'data/writer.dart';
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
import 'features/settings/settings_screen.dart';
import 'features/words/words_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
  runApp(const MarginaliaApp());
}

class MarginaliaApp extends StatefulWidget {
  const MarginaliaApp({super.key});

  @override
  State<MarginaliaApp> createState() => _MarginaliaAppState();
}

class _MarginaliaAppState extends State<MarginaliaApp> {
  /// One surface, chosen once. There is no night/day SWITCH in the app — the
  /// day/night distinction was removed, not renamed. This is an appearance
  /// preference that lives in Settings → The small print, with no time
  /// semantics attached to it.
  Palette _palette = Palette.warmPaper;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Marginalia',
      debugShowCheckedModeBanner: false,
      theme: MarginaliaTheme.themeFor(_palette),
      home: _Shell(
        palette: _palette,
        onTogglePalette: () => setState(() {
          _palette = _palette == Palette.warmPaper
              ? Palette.warmInk
              : Palette.warmPaper;
        }),
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell({required this.palette, required this.onTogglePalette});

  final Palette palette;
  final VoidCallback onTogglePalette;

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
  final List<Widget> _stack = <Widget>[];

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
    final String? wid = await get('writer:id');
    final String? wbase = await get('writer:base');
    final String? vbase = await get('voice:base');
    final String? vname = await get('voice:name');
    final String? vsrc = await get('voice:source');

    final (bool hasWriter, bool hasVoice) = await _keys.status();
    final String? voiceKey = await _keys.voice();

    final WriterEndpoint endpoint = WriterEndpoint.byId(wid ?? 'deepseek');

    if (!mounted) return;
    setState(() {
      _readSize = ReadSize.values.firstWhere(
        (ReadSize r) => r.label == size,
        orElse: () => ReadSize.medium,
      );
      _listenSize = ListenSize.values.firstWhere(
        (ListenSize r) => r.label == lsize,
        orElse: () => ListenSize.large,
      );
      _writerId = endpoint.id;
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
  }

  Future<void> _save(String key, String value) async {
    try {
      await _repo.setSetting(key, value);
    } catch (e) {
      debugPrint('could not save $key: $e');
    }
  }

  /// Save the reading plan. Seven fields plus the reader's own words, and the
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
          topic: a.topic,
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
  QueueSlot _freePlan() {
    _planCounter++;
    return QueueSlot(
      articleId: 'plan-${DateTime.now().millisecondsSinceEpoch}-$_planCounter',
      state: SlotState.planned,
      topic: 'Free pick',
      focus: 'whatever the plan suggests',
      plannedWords: 300,
      plannedMarked: 6,
    );
  }

  void _push(Widget screen) => setState(() => _stack.add(screen));

  void _pop() {
    if (_stack.isEmpty) return;
    setState(() => _stack.removeLast());
  }

  /// The startup notice. Shown ONCE, and only when something is actually
  /// missing.
  ///
  /// It is not a gate: the app is fully usable with neither key, so the notice
  /// says exactly that and offers a button rather than demanding an answer. Two
  /// buttons, no third: `Set up now` and `Not now`.
  Future<void> _maybeShowSetupNotice() async {
    final (bool hasWriter, bool hasVoice) = await _keys.status();
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
                _push(_settings());
              },
            ),
            const SizedBox(height: 8),
            Btn(
              label: 'Not now',
              primary: false,
              onPressed: () => Navigator.of(ctx).pop(),
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
      child: _stack.isNotEmpty ? _stack.last : _root(),
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
                onTap: () => _push(_settings()),
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
          ),
        const SizedBox(height: 4),
        const _Notice(),
        const SizedBox(height: 14),
        // "What are they about?" used to sit here as a full-width button that
        // opened the SAME settings screen as the ⌄ icon three rows above, with a
        // paragraph explaining what the button underneath it already said. Two
        // controls for one destination, one of them a paragraph. Removed: the
        // icon is the settings entry, and the sentence below the cards is where
        // that promise belongs.
        Text(
          'Nothing to confirm. The app records what you touched and never asks '
          'whether you remember.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.65,
            color: context.colors.ink3,
          ),
        ),
      ],
    );
  }

  /// The card's ⋯ menu. Three real actions, matching the prototype's
  /// article menu: a different topic, write it again, done with it.
  Future<void> _slotMenu(BuildContext context, Queue q, int index) async {
    final QueueSlot slot = q.slots[index];
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
              slot.isPlanned ? slot.topicLabel : 'What to do with it',
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
              _menuRow('Choose another topic', 'free, and rewrites nothing',
                  () async {
                Navigator.of(ctx).pop();
                await _changeTopic(q, index);
              }),
              _menuRow('A different plan', 'free · no input needed', () async {
                Navigator.of(ctx).pop();
                _reroll(q, index);
              }),
            ] else ...<Widget>[
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
              _menuRow('Write it again', 'costs one call', () async {
                Navigator.of(ctx).pop();
                await _write(q, index);
              }),
              _menuRow('Done with it',
                  'it leaves the queue and goes to your library', () async {
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
    await _repo.saveQueue(q);
    setState(() {});
    Toast.show(context,
        '${retired.title} is in your library · a plan took its place');
  }

  /// Change a planned card's topic through the preset chips, which is where the
  /// prototype keeps them too.
  Future<void> _changeTopic(Queue q, int index) async {
    final List<String> presets = await _repo.presets('topic');
    final List<String> choices = presets.isEmpty
        ? <String>['C language', 'NVDA', 'Music', 'Git', 'Reading']
        : presets;

    if (!mounted) return;
    final String? picked = await AppSheet.show<String>(
      context,
      title: 'What it is about',
      builder: (BuildContext ctx) => Padding(
        padding:
            const EdgeInsets.fromLTRB(Gap.sheetPad, 0, Gap.sheetPad, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                for (final String t in choices)
                  Pill(t,
                      mono: false, onTap: () => Navigator.of(ctx).pop(t)),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Changing a plan costs nothing. Nothing is written until you '
              'tap Write it.',
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 13,
                height: 1.6,
                color: ctx.colors.ink3,
              ),
            ),
          ],
        ),
      ),
    );

    if (picked == null) return;
    q.editPlan(index, topic: picked);
    await _repo.saveQueue(q);
    if (!mounted) return;
    setState(() {});
    Toast.show(context, 'plan updated · nothing written, nothing paid');
  }

  /// Open a ready card. A planned card has nothing to open, so this is never
  /// reached from one.
  void _openArticle(QueueSlot slot, {bool fromLibrary = false}) {
    if (slot.article == null) return;
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
    final Article? full = _samples[slot.articleId]?.toArticle();
    if (full == null) return slot;
    return QueueSlot(
      articleId: slot.articleId,
      state: slot.state,
      article: full,
      topic: slot.topic,
      focus: slot.focus,
      plannedWords: slot.plannedWords,
      plannedMarked: slot.plannedMarked,
      isWriting: slot.isWriting,
    );
  }

  /// The full article behind a slot identity. A bundled sample carries its own
  /// text; a written article is in memory too, since Write it produced it here.
  Article? _articleFor(String id) =>
      _samples[id]?.toArticle() ?? _written[id];

  /// Articles this phone paid for, kept in memory for the session. The body is
  /// NOT in the database: only its identity and counts are, which is what lets a
  /// written article be re-opened without a second copy of the text in two
  /// places.
  final Map<String, Article> _written = <String, Article>{};

  /// THE ONLY PATH THAT COSTS MONEY, and it is a tap.
  Future<void> _write(Queue q, int index) async {
    final QueueSlot slot = q.slots[index];
    if (!slot.isPlanned) {
      Toast.show(context, 'that one is already written');
      return;
    }

    final String? key = await _keys.writer();
    if (key == null || key.trim().isEmpty) {
      Toast.show(context, 'no writer key is saved — nothing was spent');
      _push(_settings());
      return;
    }

    final WriterEndpoint ep = WriterEndpoint.byId(_writerId);
    // The card shows it is working, so a tap cannot become a second call while
    // the first is still in flight.
    q.slots[index].isWriting = true;
    setState(() {});

    try {
      final Article article = await _writer.write(
        articleId: slot.articleId,
        topic: slot.topicLabel,
        focus: slot.focus,
        plan: _plan,
        words: slot.plannedWords > 0 ? slot.plannedWords : _plan.length,
        marked: slot.plannedMarked > 0 ? slot.plannedMarked : _plan.marked,
        apiKey: key,
        endpoint: ep,
      );
      _written[article.id] = article;
      q.writeSlot(index, article);
      await _repo.saveQueue(q);
      await _repo.recordLedger(
        articleId: article.id,
        title: article.title,
        topic: article.topic,
        kilobytes: (article.wordCount * 6 ~/ 1024) + 1,
      );
      if (!mounted) return;
      setState(() {});
      Toast.show(context,
          '${article.title} is ready · ~${article.wordCount} words · one call');
    } on RemoteFailure catch (e) {
      if (!mounted) return;
      setState(() {});
      Toast.show(context, e.message, duration: const Duration(seconds: 5));
    } catch (e) {
      if (!mounted) return;
      setState(() {});
      Toast.show(context, 'nothing was written · $e',
          duration: const Duration(seconds: 5));
    }
  }

  /// Reroll is free, needs no input, and never touches money.
  void _reroll(Queue q, int index) {
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
      size: _listenSize,
      onSize: (ListenSize s) {
        setState(() => _listenSize = s);
        unawaited(_save('ui:listenSize', s.label));
      },
      onCountListen: () => _countListen(a),
    );
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
          child: _listeningOn ? listen : read,
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
    setState(() => _speakingIndex = index);
    await _audio.play(index, a.sentences[index].english);
    if (mounted) setState(() => _speakingIndex = -1);
  }

  /// Invariant 3: this counts and the article STAYS. Nothing is removed.
  Future<void> _countRead(Article a) async {
    await _repo.countRead(
      articleId: a.id,
      title: a.title,
      topic: a.topic,
      day: todayDay(),
      minutes: a.minuteEstimate,
    );
    if (!mounted) return;
    Toast.show(context, 'counted. it stays in your queue.');
    setState(() {});
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
    );
  }

  // ── settings ──────────────────────────────────────────────────────────

  Widget _settings() {
    return SettingsScreen(
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
        paletteName: widget.palette.name,
        dictionaryEntries: _dict?.size ?? 0,
      ),
      onBack: _pop,
      onPlanChanged: _savePlan,
      onToggleAppearance: widget.onTogglePalette,
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
        if (mounted) setState(() {});
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
          return e.message;
        } catch (e) {
          return '$e';
        }
      },
    );
  }

  bool _hasWriterKey = false;
  bool _hasVoiceKey = false;

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
class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Every word and every sentence has sound',
            style: TextStyle(
              fontFamily: TypeScale.sans,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'tap a word for its meaning · hold a line to hear it · the Listen '
            'tab plays the whole thing',
            style: TextStyle(
              fontFamily: TypeScale.sans,
              fontSize: 12.5,
              height: 1.5,
              color: c.ink3,
            ),
          ),
        ],
      ),
    );
  }
}