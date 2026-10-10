// The debug log.
//
// This screen exists because the writer is an agent now. An agent makes several
// calls, can fail at any of them, and then reduces all of it to one sentence for
// the reader — "the writer did not produce a usable article". That sentence is
// true and useless. The only way to answer it would otherwise be to pay for
// another run and watch, which is the worst possible debugging loop: slow,
// expensive, and not repeatable.
//
// So the log is a first-class screen rather than a developer flag. It is in the
// hub, one tap from Settings, and its most important control is **Copy all** —
// because the person who needs to read it is usually not the person holding the
// phone.
//
// The list is grouped by RUN, not by line. A flat list of 300 entries with
// `12:04:07 · plan · rmuy…` on every one answers none of the questions a
// reader brings here: when was this, what was being done, which article, and
// did it work. One card per run, with those four answers on the card, is the
// difference between a log and a wall of timestamps.
//
// Newest first. A log is read from the thing that just happened backwards, and a
// list that makes you scroll to the bottom to find out why your article failed
// has made the common case the expensive one.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../core/design/tokens.dart';
import '../../core/widgets/back_label.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/texture.dart' show Hairline;
import '../../data/remote/log.dart';

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  /// Which things are open. A run opens as a whole (keyed by runId); a single
  /// step opens its detail (keyed by seq, namespaced so a seq cannot collide
  /// with a runId).
  final Set<String> _open = <String>{};

  String _runKey(LogRun r) => 'run:${r.runId}';
  String _stepKey(LogEntry e) => 'step:${e.seq}';

  @override
  void initState() {
    super.initState();
    AgentLog.instance.addListener(_tick);
  }

  @override
  void dispose() {
    AgentLog.instance.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: AgentLog.instance.dump()));
    if (!mounted) return;
    Toast.show(context, 'the whole log is on your clipboard');
  }

  /// Clearing asks first, and the question says what is lost. The log is the
  /// only record of a run that has already been paid for — a one-tap wipe of
  /// unreproducible evidence is a bad button.
  Future<void> _clear() async {
    final bool? yes = await AppSheet.show<bool>(
      context,
      builder: (BuildContext ctx) => _ConfirmClear(
        count: AgentLog.instance.entries.length,
      ),
    );
    if (yes != true || !mounted) return;
    AgentLog.instance.clear();
    if (!mounted) return;
    setState(_open.clear);
  }

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final List<LogRun> runs = AgentLog.instance.groups();
    // Newest run first; inside a run, oldest first — that is the order things
    // happened, and a timeline read upside down is a timeline that lies.
    final List<LogRun> shown = runs;

    return PageScaffold(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, 4, Gap.gutter, 0),
            child: Row(
              children: <Widget>[
                BackLabel(label: '‹ Settings', onTap: widget.onBack),
                const Spacer(),
                if (AgentLog.instance.entries.isNotEmpty) ...<Widget>[
                  _MiniBtn(label: 'Copy all', onTap: _copyAll),
                  const SizedBox(width: 8),
                  _MiniBtn(label: 'Clear', onTap: _clear),
                ],
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? _empty(c)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                        Gap.gutter, 12, Gap.gutter, 30),
                    itemCount: shown.length + 1,
                    itemBuilder: (BuildContext ctx, int i) {
                      if (i == 0) return _intro(c);
                      return _runCard(c, shown[i - 1]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _intro(Palette c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        'One card per thing the app asked for, newest first. Tap a card to see '
        'it call by call. Nothing here is sent anywhere — it lives in this app '
        'and disappears when the app is closed. No key and no full article is '
        'ever written down.',
        style: TextStyle(
          fontFamily: TypeScale.serif,
          fontSize: 13,
          height: 1.65,
          color: c.ink3,
        ),
      ),
    );
  }

  Widget _empty(Palette c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Nothing has been written yet',
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap Write a new one on a card and the run will appear here, '
              'call by call. This is where to look when an article fails.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 13.5,
                height: 1.65,
                color: c.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One run: the question on the card, the timeline under it.
  Widget _runCard(Palette c, LogRun run) {
    final bool open = _open.contains(_runKey(run));
    final bool failed = run.outcome == 'failed';
    final Color dot = switch (run.outcome) {
      'finished' => c.jade,
      'failed' => c.verm,
      _ => c.ink3,
    };
    final String outcome = run.outcome;
    final int calls = run.entries
        .where((LogEntry e) => e.phase == 'http')
        .length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: Radii.cardAll,
          onTap: () => setState(() {
            if (open) {
              _open.remove(_runKey(run));
            } else {
              _open.add(_runKey(run));
            }
          }),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: Radii.cardAll,
              border: Border.all(color: failed ? c.verm : c.hair),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration:
                            BoxDecoration(color: dot, shape: BoxShape.circle),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // WHAT was being done. The label the run was started
                          // with, which carries the subject when there was one.
                          Text(
                            run.label,
                            style: TextStyle(
                              fontFamily: TypeScale.serif,
                              fontSize: 15,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // WHEN and HOW IT ENDED, in one quiet line.
                          Text(
                            '${run.started.month}-${_two(run.started.day)} '
                            '${_two(run.started.hour)}:${_two(run.started.minute)}'
                            ' · $outcome'
                            '${calls > 0 ? ' · $calls model call${calls == 1 ? '' : 's'}' : ''}'
                            ' · ${run.entries.length} step${run.entries.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontFamily: TypeScale.mono,
                              fontSize: 10.5,
                              color: c.ink3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      open ? '⌃' : '⌄',
                      style: TextStyle(fontSize: 13, color: c.ink3),
                    ),
                  ],
                ),
                if (open) ...<Widget>[
                  const SizedBox(height: 12),
                  Hairline(color: c.hair),
                  const SizedBox(height: 10),
                  for (final LogEntry e in run.entries) _step(c, e),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// One step inside a run. Time on the left, what happened on the right.
  Widget _step(Palette c, LogEntry e) {
    final bool open = _open.contains(_stepKey(e));
    final (Color dot, String level) = switch (e.level) {
      LogLevel.info => (c.jade, ''),
      LogLevel.warn => (c.verm, 'warn'),
      LogLevel.error => (c.verm, 'error'),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => setState(() {
            if (open) {
              _open.remove(_stepKey(e));
            } else {
              _open.add(_stepKey(e));
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // The clock. Milliseconds matter here — the gap between two
                // lines is often the whole diagnosis.
                SizedBox(
                  width: 62,
                  child: Text(
                    e.clock,
                    style: TextStyle(
                      fontFamily: TypeScale.mono,
                      fontSize: 9.5,
                      height: 1.5,
                      color: c.ink3,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration:
                        BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        e.title,
                        style: TextStyle(
                          fontFamily: TypeScale.serif,
                          fontSize: 13.5,
                          height: 1.45,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          e.phaseWord,
                          if (level.isNotEmpty) level,
                        ].join(' · '),
                        style: TextStyle(
                          fontFamily: TypeScale.mono,
                          fontSize: 9.5,
                          color: c.ink3,
                        ),
                      ),
                      if (open && e.detail.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: c.paperSunk,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: c.hair),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                for (final MapEntry<String, Object?> kv
                                    in e.detail.entries)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(
                                      '${_detailWord(kv.key)}: ${kv.value}',
                                      style: TextStyle(
                                        fontFamily: TypeScale.mono,
                                        fontSize: 10.5,
                                        height: 1.5,
                                        color: c.ink2,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (e.detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, top: 3),
                    child: Text(
                      open ? '⌃' : '⌄',
                      style: TextStyle(fontSize: 12, color: c.ink3),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Detail keys in words a reader can use. `reqBytes` is not.
  static String _detailWord(String k) => switch (k) {
        'what' => 'what',
        'model' => 'model',
        'endpoint' => 'service',
        'tools' => 'research tools',
        'tool' => 'tool',
        'turn' => 'round',
        'attempt' => 'try',
        'ms' => 'took',
        'wallClockMs' => 'took (ms)',
        'reqBytes' => 'sent (bytes)',
        'resBytes' => 'back (bytes)',
        'contentChars' => 'answer (chars)',
        'modelCalls' => 'model calls',
        'spentCalls' => 'paid calls',
        'toolCalls' => 'research calls',
        'turns' => 'rounds',
        'system' => 'prompt (chars)',
        'user' => 'your request (chars)',
        'why' => 'why',
        'error' => 'error',
        'reason' => 'reason',
        'status' => 'status',
        _ => k,
      };
}

/// A small flat button, for the two actions in the toolbar.
class _MiniBtn extends StatelessWidget {
  const _MiniBtn({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Material(
      color: c.paperSunk,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: c.hair),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: TypeScale.sans,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: c.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmClear extends StatelessWidget {
  const _ConfirmClear({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sheetPad, 0, Gap.sheetPad, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Clear the log?',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'All $count lines go, including the record of runs you have '
            'already paid for. Copy them first if you might need them.',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13.5,
              height: 1.6,
              color: c.ink3,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: Btn(
                  label: 'Keep them',
                  primary: false,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Btn(
                  label: 'Clear',
                  primary: true,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
