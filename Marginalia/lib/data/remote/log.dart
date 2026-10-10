// The debug log for a writing run.
//
// This exists because the writer became an agent, and an agent is a thing that
// makes several calls, fails in several places, and then says one sentence to
// the reader. Without a record of what actually happened, "the writer did not
// produce a usable article" is unanswerable — and the only way to answer it
// would be to pay for another run.
//
// So: every model request, every tool call and a summary of every run, in a
// ring buffer the reader can open from Settings. In memory, not on disk — a log
// write on the hot path of every request is a cost this does not need, and a
// debugging session rarely spans a restart.
//
// NEVER LOGGED: any API key, any Authorization header, or a full article body.
// Bodies appear only as counts and a short scrubbed snippet.

// NO FLUTTER IMPORT, and that is load-bearing rather than tidy. `tool/
// check_agent.dart` drives this whole layer from a plain Dart program, and one
// `package:flutter/foundation.dart` anywhere in the chain pulls in `dart:ui`,
// which does not exist outside a Flutter engine. The agent is pure Dart so it
// can be tested without one.

import 'dart:collection';

import '../../domain/agent_budget.dart';

enum LogLevel { info, warn, error }

/// One line. [runId] is what makes a run legible: every line from one tap on
/// Write it carries the same id, so a failure can be read end to end.
class LogEntry {
  LogEntry({
    required this.seq,
    required this.at,
    required this.level,
    required this.phase,
    required this.title,
    this.runId = '',
    this.runLabel = '',
    Map<String, Object?> detail = const <String, Object?>{},
  }) : detail = Map<String, Object?>.unmodifiable(detail);

  final int seq;
  final DateTime at;
  final LogLevel level;

  /// `plan` · `turn` · `http` · `tool` · `parse` · `done`
  final String phase;
  final String title;
  final String runId;

  /// What the run was FOR, in words a reader owns: `Writing an article about
  /// pointers`, `Rewriting your reading plan`. Empty for ambient lines (a news
  /// fetch, a search) that are not part of any run.
  ///
  /// This is the field that answers "which article is this about?" — without
  /// it the log is a pile of clock times and model names.
  final String runLabel;
  final Map<String, Object?> detail;

  /// `14:03:07.318` — local, millisecond precision. Millisecond precision is
  /// not decoration: the difference between a 400 ms tool call and a 12 s one
  /// is most of a diagnosis.
  String get clock {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}'
        '.${at.millisecond.toString().padLeft(3, '0')}';
  }

  /// `10月11日 14:03` — for a run header. A log that spans several days and
  /// shows only a clock is a log in which every line looks like today.
  String get dayClock {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }

  /// The phase in words a reader already knows. `http` is not a step anyone
  /// takes; "calling the model" is.
  String get phaseWord => switch (phase) {
        'plan' => 'start',
        'turn' => 'thinking',
        'http' => 'call',
        'tool' => 'research',
        'parse' => 'reading the answer',
        'done' => 'finish',
        _ => phase,
      };

  /// The line as the log screen renders it, and as "Copy all" produces it.
  String get line {
    final StringBuffer b = StringBuffer(
        '$dayClock  ${level.name.toUpperCase()}  $phaseWord  $title');
    if (runLabel.isNotEmpty) b.write('\n    what: $runLabel');
    if (detail.isNotEmpty) {
      detail.forEach((String k, Object? v) {
        b.write('\n    $k: $v');
      });
    }
    return b.toString();
  }
}

/// A finished (or in-flight) run, collected for display.
///
/// The log screen does not show a flat list of 300 lines. It shows this: one
/// card per run, with the question the reader actually has answered on the
/// card — what was being done, to which article, and did it work.
class LogRun {
  LogRun({required this.runId, required this.label, required this.entries});

  final String runId;
  final String label;
  final List<LogEntry> entries;

  DateTime get started => entries.first.at;

  /// A run is OK if it ended with an info `done` line ("finished OK"). An
  /// error anywhere, or no closing line at all, is not a success — and a card
  /// that claims otherwise is the one lie this screen must not tell.
  bool get ok => entries.any((LogEntry e) =>
      e.phase == 'done' &&
      e.level == LogLevel.info &&
      !e.title.startsWith('failed'));

  bool get hasError =>
      entries.any((LogEntry e) => e.level == LogLevel.error);

  /// `finished` · `failed` · `still running`. Three states, because a run
  /// that is mid-flight is not a failure and must not look like one.
  String get outcome {
    if (ok) return 'finished';
    if (hasError) return 'failed';
    return 'still running';
  }
}

/// The ring buffer. One instance, reached by `AgentLog.instance`.
class AgentLog {
  AgentLog._();

  static final AgentLog instance = AgentLog._();

  final Queue<LogEntry> _entries = Queue<LogEntry>();
  final Map<String, String> _runLabels = <String, String>{};
  int _seq = 0;

  /// Plain callbacks rather than a `ValueNotifier`, so this file needs no
  /// Flutter. A log screen subscribes in `initState` and drops it in `dispose`.
  final List<void Function()> _listeners = <void Function()>[];

  void addListener(void Function() f) => _listeners.add(f);
  void removeListener(void Function() f) => _listeners.remove(f);

  /// Newest LAST, which is the order they happened. The screen reverses it.
  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  /// Tell the log what this run is for. Called once, when the run starts.
  ///
  /// Every later line carrying the same [runId] is stamped with [label], so a
  /// reader scrolling the log never has to decode an id to know which article
  /// a call belongs to.
  void beginRun(String runId, String label) {
    if (runId.isEmpty) return;
    _runLabels[runId] = label;
    // Prune labels of runs that have fallen out of the ring, so a long-lived
    // session does not accumulate a map bigger than the log it describes.
    if (_runLabels.length > kLogRingSize) {
      final Set<String> live = <String>{for (final LogEntry e in _entries) e.runId};
      _runLabels.removeWhere((String k, String _) => !live.contains(k));
    }
  }

  void add(
    LogLevel level,
    String phase,
    String title, {
    String runId = '',
    Map<String, Object?> detail = const <String, Object?>{},
  }) {
    final LogEntry e = LogEntry(
      seq: _seq++,
      at: DateTime.now(),
      level: level,
      phase: phase,
      title: title,
      runId: runId,
      runLabel: runId.isEmpty ? '' : (_runLabels[runId] ?? ''),
      detail: detail,
    );
    _entries.addLast(e);
    while (_entries.length > kLogRingSize) {
      _entries.removeFirst();
    }
    // Also to stdout, which on Android is logcat — so a run can be read with
    // `adb logcat` when the phone is in someone else's hands. The in-app screen
    // is still the primary surface, because it is the one the READER can use.
    print('[${e.phase}] ${e.title}'
        '${e.detail.isEmpty ? '' : ' ${e.detail}'}');
    for (final void Function() f in List<void Function()>.of(_listeners)) {
      f();
    }
  }

  void info(String phase, String title,
          {String runId = '', Map<String, Object?> detail = const <String, Object?>{}}) =>
      add(LogLevel.info, phase, title, runId: runId, detail: detail);

  void warn(String phase, String title,
          {String runId = '', Map<String, Object?> detail = const <String, Object?>{}}) =>
      add(LogLevel.warn, phase, title, runId: runId, detail: detail);

  void error(String phase, String title,
          {String runId = '', Map<String, Object?> detail = const <String, Object?>{}}) =>
      add(LogLevel.error, phase, title, runId: runId, detail: detail);

  void clear() {
    _entries.clear();
    _runLabels.clear();
    for (final void Function() f in List<void Function()>.of(_listeners)) {
      f();
    }
  }

  /// Newest first, one card per run, ambient lines under their own heading.
  ///
  /// This is the shape the screen draws and the shape Copy all should produce:
  /// a reader handed the log should see "Writing an article about pointers
  /// failed at the second call" without decoding anything.
  List<LogRun> groups() {
    final Map<String, List<LogEntry>> byRun = <String, List<LogEntry>>{};
    final List<LogEntry> ambient = <LogEntry>[];
    for (final LogEntry e in _entries) {
      if (e.runId.isEmpty) {
        ambient.add(e);
      } else {
        byRun.putIfAbsent(e.runId, () => <LogEntry>[]).add(e);
      }
    }
    // Runs in the order they STARTED, newest first — the reader opens this
    // screen because of the thing that just failed.
    final List<String> runIds = byRun.keys.toList()
      ..sort((String a, String b) =>
          byRun[b]!.first.at.compareTo(byRun[a]!.first.at));
    final List<LogRun> out = <LogRun>[
      for (final String id in runIds)
        LogRun(
          runId: id,
          label: _runLabels[id] ?? 'Something the app asked for',
          entries: byRun[id]!,
        ),
    ];
    if (ambient.isNotEmpty) {
      out.add(LogRun(
        runId: '',
        label: 'Other things the app did',
        entries: ambient,
      ));
    }
    return out;
  }

  /// Everything, oldest first, as text for the clipboard.
  ///
  /// This is the feature that makes the log useful to somebody who is not
  /// holding the phone: the reader taps Copy all and pastes the run into a
  /// message. Grouped by run, with the label on the first line of each.
  String dump() {
    if (_entries.isEmpty) return '(the log is empty)';
    final StringBuffer b = StringBuffer();
    for (final LogRun run in groups().reversed) {
      if (b.isNotEmpty) b.writeln();
      b.writeln('── ${run.label} · ${run.outcome} · ${run.started}');
      for (final LogEntry e in run.entries) {
        b.writeln(e.line);
      }
    }
    return b.toString().trimRight();
  }

  /// Hide anything that looks like a credential.
  ///
  /// Called on every string that could have come from a request or a response.
  /// The rule is deliberately blunt — a key is long, has no spaces, and is the
  /// only thing here that would be a disaster to leak — so anything matching a
  /// known prefix or a long unbroken run of key characters is cut down to its
  /// first four characters and its length.
  static String scrub(String s, {Iterable<String> knownKeys = const <String>[]}) {
    String out = s;
    for (final String k in knownKeys) {
      if (k.length >= 8) out = out.replaceAll(k, _mask(k));
    }
    // sk-…, uapi-…, tp-… and bare long tokens in a header-ish position.
    out = out.replaceAllMapped(
      RegExp(r'\b(sk|uapi|tp|ttp|Bearer)[- ]([A-Za-z0-9_\-]{16,})'),
      (Match m) => '${m[1]} ${_mask(m[2]!)}',
    );
    out = out.replaceAllMapped(
      RegExp(r'\b[A-Za-z0-9_\-]{32,}\b'),
      (Match m) => _mask(m[0]!),
    );
    return out;
  }

  static String _mask(String k) =>
      k.length <= 4 ? '****' : '${k.substring(0, 4)}…(${k.length} chars)';

  /// A short, scrubbed excerpt of a response body, for the log.
  static String snippet(String body, {Iterable<String> knownKeys = const <String>[]}) {
    final String s = scrub(body, knownKeys: knownKeys)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.length <= kLogBodySnippetChars) return s;
    return '${s.substring(0, kLogBodySnippetChars)}…';
  }
}
