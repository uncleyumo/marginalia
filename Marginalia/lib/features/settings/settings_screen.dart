// Settings: a hub and four panes.
//
// The hub restates whatever the panes hold. That is its whole purpose — a
// settings screen that only lists labels is a settings screen you have to open
// four times to check anything. DESIGN's rule: the hub row is LIVE, "four lines
// that state the truth", not four links with a title.
//
// Re-entering Settings always lands on the hub, never on the last pane used.
// That is not memory, it is an admission that we did not know what you came
// back for.
//
// EVERY CONTROL HERE DOES SOMETHING. The previous version had rows that reported
// "no key saved — nothing to test", a MiMo card whose tap said "MiMo needs a key
// — see below" with nothing below it, and an Appearance row that borrowed
// `PlanField.reader`'s label so the surface's name appeared under the word
// READER. A settings screen full of controls that explain why they cannot be used
// is a worse thing than no settings screen, so each pane below is wired to a real
// write and a real test.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/back_label.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/texture.dart' show Hairline;
import '../../data/audio.dart';
import '../../data/remote/api.dart';
import '../../data/remote/log.dart';
import '../../domain/instruction.dart';
import '../../domain/plan.dart';
import 'plan_rewrite_sheet.dart';

enum Pane {
  hub,
  articles,
  appearance,
  instructions,
  voice,
  listening,
  writer,
  smallPrint,
}

/// Everything the panes need to read and write, handed in from main so this
/// screen holds no state of its own beyond which pane is open.
class SettingsModel {
  const SettingsModel({
    required this.plan,
    required this.writerId,
    required this.writerBase,
    required this.writerKeySaved,
    required this.voiceSource,
    required this.voiceBase,
    required this.voiceName,
    required this.voiceKeySaved,
    required this.deviceVoice,
    required this.appearance,
    required this.face,
    required this.listenAutoPlay,
    required this.listenAutoContinue,
    required this.listenAutoContinueCount,
    required this.listenAutoOrder,
    required this.dictionaryEntries,
    required this.newsKeySaved,
    required this.newsOn,
    required this.searchKeySaved,
    required this.searchOn,
    required this.version,
    required this.build,
  });

  final ReadingPlan plan;

  /// Which writer is selected. 'deepseek' | 'openai' | 'mimo'.
  final String writerId;
  final String writerBase;
  final bool writerKeySaved;

  /// 'device' | 'mimo'.
  final String voiceSource;
  final String voiceBase;
  final String voiceName;
  final bool voiceKeySaved;
  final DeviceVoice deviceVoice;

  /// Which surface, and which face the article is set in. Both are appearance,
  /// both live in the Appearance pane, and neither is a colour.
  final AppearanceMode appearance;
  final ReadingFace face;

  /// How the listening screen behaves. The stored spellings match main's
  /// keys: autoPlay is 'off'/'on', autoContinue is 'off'/'forever'/'count'/
  /// 'loop', autoOrder is one of the five `_orderWord` cases below.
  final bool listenAutoPlay;
  final String listenAutoContinue;
  final int listenAutoContinueCount;
  final String listenAutoOrder;

  /// 0 while the dictionary is still inflating. Shown honestly rather than
  /// hidden, because "392,695 words" is the promise and its absence is a fault.
  final int dictionaryEntries;

  /// The two OPTIONAL sources the writer may consult. Neither is required and
  /// neither is part of "is this app set up" — a reader with no keys at all
  /// still gets articles, so the setup notice deliberately ignores both.
  ///
  /// [newsOn] and [searchOn] are separate from the keys on purpose: saving a key
  /// turns the source on, and the switch lets it be turned off again without
  /// having to delete the key and paste it back later.
  final bool newsKeySaved;
  final bool newsOn;
  final bool searchKeySaved;
  final bool searchOn;

  /// What Android says is installed: `versionName` and `versionCode`.
  ///
  /// Read from the package manager rather than from a constant in the source,
  /// because the question this answers is "is the phone running the build I
  /// just made?" — and a constant in the source answers a different question,
  /// namely "what did somebody remember to type". Empty while the read is in
  /// flight; the row says so rather than showing a wrong number.
  final String version;
  final String build;

  bool get hasWriter => writerKeySaved;
  bool get hasVoice => voiceSource == 'mimo' ? voiceKeySaved : true;

  WriterEndpoint get writer => WriterEndpoint.byId(writerId);

  /// The hub row's value line. States both switches and the order, because a
  /// row that only says "Listening" makes the reader open the pane to learn
  /// something the row could have said — the hub's whole job.
  String get listeningLine {
    final String open = listenAutoPlay ? 'plays on open' : 'does not auto-play';
    final String cont = switch (listenAutoContinue) {
      'forever' => 'keeps going, ${orderWord(listenAutoOrder)}',
      'count' =>
        'continues ${orderWord(listenAutoOrder)} · $listenAutoContinueCount times',
      'loop' => 'loops the current article',
      _ => 'no auto-continue',
    };
    return '$open · $cont';
  }

  /// The five order values as short words, for the hub line and the pane.
  static String orderWord(String order) => switch (order) {
    'oldest' => 'oldest',
    'mostStudied' => 'most studied',
    'leastStudied' => 'least studied',
    'random' => 'random',
    _ => 'newest',
  };
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.model,
    this.initialPane = Pane.hub,
    required this.onBack,
    required this.onPlanChanged,
    required this.onRewritePlan,
    required this.onAppearance,
    required this.onFace,
    required this.onWriterSelected,
    required this.onWriterBaseChanged,
    required this.onWriterKeyChanged,
    required this.onVoiceSelected,
    required this.onVoiceBaseChanged,
    required this.onVoiceNameChanged,
    required this.onVoiceKeyChanged,
    required this.onListenAutoPlay,
    required this.onListenAutoOrder,
    required this.onProbeVoice,
    required this.onTestWriter,
    required this.onLoadInstructions,
    required this.onSaveInstruction,
    required this.onDeleteInstruction,
    required this.onNewsKeyChanged,
    required this.onNewsToggled,
    required this.onTestNews,
    required this.onSearchKeyChanged,
    required this.onSearchToggled,
    required this.onTestSearch,
    required this.onOpenDebugLog,
  });

  final SettingsModel model;

  /// Where to open. The queue's "See all saved instructions" link comes
  /// straight here; everything else lands on the hub, which is what re-entering
  /// Settings from the queue should do.
  final Pane initialPane;

  final VoidCallback onBack;
  final void Function(ReadingPlan plan) onPlanChanged;

  /// Does the AI plan rewrite. Null when there is no key saved, which is what
  /// disables the button rather than letting it fail at the network.
  final Future<PlanRewrite> Function(String request)? onRewritePlan;

  final ValueChanged<AppearanceMode> onAppearance;
  final ValueChanged<ReadingFace> onFace;

  final void Function(String id) onWriterSelected;
  final void Function(String base) onWriterBaseChanged;
  final void Function(String key) onWriterKeyChanged;

  final void Function(String source) onVoiceSelected;
  final void Function(String base) onVoiceBaseChanged;
  final void Function(String name) onVoiceNameChanged;
  final void Function(String key) onVoiceKeyChanged;

  // ── listening ─────────────────────────────────────────────────────────
  //
  // Three calls rather than one, because the three prefs are saved under
  // three keys and the continue mode pairs with the count every time it is
  // written — one callback that took all four values would make every chip
  // resay the other three.

  final ValueChanged<bool> onListenAutoPlay;

  /// 'newest' | 'oldest' | 'mostStudied' | 'leastStudied' | 'random'.
  final ValueChanged<String> onListenAutoOrder;

  /// Both return null on success or a sentence to show.
  final Future<String?> Function() onProbeVoice;
  final Future<String?> Function() onTestWriter;

  // ── instructions ──────────────────────────────────────────────────────
  //
  // Three calls rather than one repository handle, because this screen has no
  // business holding a database and every pane above it is wired the same way.

  /// Everything saved, newest-used first. Called on entering the pane and after
  /// every write, so the list is never a stale copy.
  final Future<List<Instruction>> Function() onLoadInstructions;

  /// Save new ([id] null) or overwrite ([id] set). Returns the same sentence
  /// contract as the tests: null on success.
  final Future<String?> Function(String text, {String? id}) onSaveInstruction;
  final Future<String?> Function(String id) onDeleteInstruction;

  // ── the two optional sources ──────────────────────────────────────────

  final void Function(String key) onNewsKeyChanged;
  final ValueChanged<bool> onNewsToggled;
  final Future<String?> Function() onTestNews;

  final void Function(String key) onSearchKeyChanged;
  final ValueChanged<bool> onSearchToggled;
  final Future<String?> Function() onTestSearch;

  /// Opens the debug log. A callback rather than a push from here, so this
  /// screen stays a screen and not a navigator.
  final VoidCallback onOpenDebugLog;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Pane _pane = widget.initialPane;

  /// Set while a network call is in flight, so the pane can say "asking…" and the
  /// button can refuse a second press rather than firing two requests.
  bool _working = false;

  /// Null until the first read lands. Null is not zero — the hub says
  /// "reading…" rather than claiming the reader has saved nothing, which is a
  /// different and much more annoying statement.
  int? _instructionCount;

  void _go(Pane p) {
    setState(() => _pane = p);
    if (p == Pane.instructions) unawaited(_loadInstructions());
  }

  SettingsModel get m => widget.model;

  @override
  void initState() {
    super.initState();
    // The hub states the count, so it has to be read even when the reader never
    // opens the pane.
    unawaited(_refreshCount());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refreshCount() async {
    try {
      final List<Instruction> all = await widget.onLoadInstructions();
      if (mounted) setState(() => _instructionCount = all.length);
    } catch (_) {
      // A count is decoration on a hub row. Failing to read it must not take
      // the settings screen down with it.
      if (mounted) setState(() => _instructionCount = 0);
    }
  }

  String get _instructionLine {
    if (_instructionCount == null) return 'reading…';
    final int n = _instructionCount!;
    if (n == 0) {
      return 'none saved — every article is the writer\'s own choice';
    }
    return '$n saved · you can pick one when you change a card';
  }

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return PageScaffold(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, 4, Gap.gutter, 0),
            child: Row(
              children: <Widget>[
                BackLabel(
                  label: _pane == Pane.hub ? '‹ Queue' : '‹ Settings',
                  onTap: _pane == Pane.hub ? widget.onBack : () => _go(Pane.hub),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (_pane) {
              Pane.hub => _hub(c),
              Pane.articles => _articles(c),
              Pane.appearance => _appearance(c),
              Pane.instructions => _instructions(c),
              Pane.voice => _voice(c),
              Pane.listening => _listening(c),
              Pane.writer => _writer(c),
              Pane.smallPrint => _smallPrint(c),
            },
          ),
        ],
      ),
    );
  }

  // ── the hub: five live lines, not five links ──────────────────────────

  Widget _hub(Palette c) {
    final ReadingPlan p = m.plan;
    final int set = p.fieldsSet;
    // No topic in this line any more. What it states instead is how much of
    // the plan is set, which is the thing the reader can act on — "any topic"
    // was a fact about a field that no longer exists.
    final String planLine = set == 0
        ? 'nothing set — picked for you'
        : '$set of ${ReadingPlan.fieldCount} fields set · '
            '${p.mediumWords} words at medium';

    // A phone with no speech engine is a real state, and hiding it behind a
    // settings row means the reader finds out by pressing play and hearing
    // nothing. So the hub row states it outright.
    final String voiceLine;
    if (m.voiceSource == 'device') {
      voiceLine = m.deviceVoice.available
          ? 'on-device · free · offline'
          : 'on-device selected · ${m.deviceVoice.note}';
    } else {
      voiceLine = m.voiceKeySaved
          ? 'MiMo · ${m.voiceName} · free · online'
          : 'MiMo selected · no key saved yet';
    }

    final String writerLine = m.writerKeySaved
        ? '${m.writer.name} · a key is saved · ${m.writer.costLine}'
            '${m.writer.supportsVision ? ' · sees pictures' : ''}'
        : 'no key · the app works fully without one';

    final String dictLine = m.dictionaryEntries == 0
        ? 'inflating on first run…'
        : '${_commas(m.dictionaryEntries)} words · offline · \$0.00';

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 18, Gap.gutter, 30),
      children: <Widget>[
        const Eyebrow('Settings'),
        Text('Eight things, stated plainly', style: context.texts.titleLarge),
        const SizedBox(height: 18),
        _hubRow(c, 'What you read', planLine, () => _go(Pane.articles)),
        // Appearance has its own row now. It used to be buried in The small
        // print, under a heading that means "the caveats and the licences" —
        // a reader looking for the theme had to open a pane whose name says
        // the opposite of what they wanted.
        _hubRow(
          c,
          'Appearance',
          '${m.appearance.label} · ${m.face.label}',
          () => _go(Pane.appearance),
        ),
        _hubRow(
          c,
          'Instructions',
          _instructionLine,
          () => _go(Pane.instructions),
        ),
        _hubRow(c, 'Voice', voiceLine, () => _go(Pane.voice)),
        // Beside Voice because the two answer the next pair of questions a
        // listener has: WHICH engine (Voice), then WHAT IT DOES once playing
        // (here). Burying "plays on open" inside the Voice pane would make a
        // reader who only wants the phone's free engine open a pane about
        // MiMo keys to change it.
        _hubRow(c, 'Listening', m.listeningLine, () => _go(Pane.listening)),
        _hubRow(c, 'Who writes', writerLine, () => _go(Pane.writer)),
        _hubRow(
          c,
          'The small print',
          dictLine,
          () => _go(Pane.smallPrint),
        ),
        // The log is its own row rather than a line in The small print. The log
        // is not small print: it is what you open when something failed, which
        // makes it the one pane a reader visits in a hurry.
        _hubRow(
          c,
          'Debug log',
          AgentLog.instance.isEmpty
              ? 'nothing written yet'
              : '${AgentLog.instance.groups().length} thing${AgentLog.instance.groups().length == 1 ? '' : 's'} asked for · '
                  'tap to see what happened',
          widget.onOpenDebugLog,
        ),
        const SizedBox(height: 20),
        Text(
          'Nothing here is required. The app works with every one of these at '
          'its default.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13.5,
            height: 1.65,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 18),
        Hairline(color: c.hair),
        const SizedBox(height: 12),
        // The build stamp, in mono, at the very bottom of the hub.
        //
        // The hub and not a pane: during iteration the question is "is this the
        // APK I just installed?", asked while standing over the phone, and a
        // version behind two taps is a version somebody will not check. It is
        // the last thing on the page because it is the last thing anybody needs
        // on a normal day.
        Text(
          m.version.isEmpty
              ? 'version · reading it…'
              : 'version ${m.version} (${m.build})',
          style: TextStyle(
            fontFamily: TypeScale.mono,
            fontSize: 10.5,
            letterSpacing: 0.02,
            color: c.ink3,
          ),
        ),
      ],
    );
  }

  Widget _hubRow(Palette c, String title, String value, VoidCallback tap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 3),
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
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: TextStyle(
                        fontFamily: TypeScale.serif,
                        fontSize: 13.5,
                        height: 1.5,
                        color: c.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text('›', style: TextStyle(fontSize: 19, color: c.ink3)),
            ],
          ),
        ),
      ),
    );
  }

  // ── What you read: five keyword fields, then three lengths ────────────

  Widget _articles(Palette c) {
    final ReadingPlan p = m.plan;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 18, Gap.gutter, 30),
      children: <Widget>[
        Text('What you read', style: context.texts.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Read before every article, so detail here costs nothing per article.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.6,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 18),
        for (final PlanField f in PlanField.keywords)
          _FieldRow(
            field: f,
            value: _valueOf(p, f),
            onTap: () => _editField(f),
          ),

        // The three lengths, under their own heading, because they answer a
        // different question from the five above: WHAT to write, then HOW LONG.
        const SizedBox(height: 22),
        const SectionLabel('Length'),
        Text(
          'What "short", "medium" and "long" mean, in words. The queue picks '
          'one at random when it plans an article, and you can ask for a '
          'particular one — or an exact number — from a card\'s ⋯ menu.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.6,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 10),
        for (final PlanField f in PlanField.lengths)
          _FieldRow(
            field: f,
            value: _valueOf(p, f),
            onTap: () => _editField(f),
          ),
        const SizedBox(height: 8),
        Text(
          'The recommendations are $kShortWords / $kMediumWords / $kLongWords. '
          'You are not being asked how many words to mark — the writer decides '
          'that, and the app measures what it decided.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 12.5,
            height: 1.6,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 18),
        Btn(
          label: 'Edit my own words',
          primary: false,
          onPressed: () => _editRaw(),
        ),
        const SizedBox(height: 10),
        Text(
          p.raw.isEmpty
              ? 'You have not written anything in your own words. A sentence '
                  'the app cannot hold in a field still reaches the writer.'
              : 'Your words: “${p.raw}”',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.65,
            color: c.ink3,
          ),
        ),

        // The AI editor. Above the fold in spirit if not in fact: it is the
        // fastest way to a plan that fits, and it is the one control here that
        // costs money, so it says so before the button rather than after.
        const SizedBox(height: 26),
        Hairline(color: c.hair),
        const SizedBox(height: 18),
        Btn(
          label: '✦ Ask the AI to change it',
          primary: true,
          onPressed: widget.onRewritePlan == null ? null : _askAi,
        ),
        const SizedBox(height: 8),
        Text(
          'Say what should change in your own words and the writer proposes a '
          'new plan. You see the difference before anything is saved.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 12.5,
            height: 1.6,
            color: c.ink3,
          ),
        ),

        // ── the way back ────────────────────────────────────────────────
        //
        // A settings page that can only be edited in one direction is a page
        // people stop editing: the fields are free text, the AI editor adds
        // more, and after a few weeks nobody remembers which of the seven they
        // changed or what the numbers used to be. Restoring is the only way to
        // find out, and without it the honest advice is "don't touch it".
        //
        // It is at the BOTTOM because it is the least common thing here, and it
        // is separated by a rule because it undoes everything above it.
        const SizedBox(height: 26),
        Hairline(color: c.hair),
        const SizedBox(height: 18),
        Btn(
          label: 'Restore the defaults',
          primary: false,
          onPressed: m.plan == const ReadingPlan() ? null : _restoreDefaults,
        ),
        const SizedBox(height: 8),
        Text(
          m.plan == const ReadingPlan()
              ? 'Nothing to restore — this is already what a fresh install has.'
              : 'Puts all seven fields back to what a fresh install has, '
                  'including the three lengths, and clears anything you wrote '
                  'in your own words. Articles already written are not touched.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 12.5,
            height: 1.6,
            color: c.ink3,
          ),
        ),
      ],
    );
  }

  /// Ask first, then reset. Same sheet shape as every other confirmation in
  /// this app — there is not one `AlertDialog` in the codebase.
  Future<void> _restoreDefaults() async {
    final bool? yes = await AppSheet.show<bool>(
      context,
      builder: (BuildContext ctx) => const _ConfirmRestore(),
    );
    if (yes != true || !mounted) return;
    widget.onPlanChanged(const ReadingPlan());
    Toast.show(context, 'the plan is back to its defaults · nothing else moved');
  }

  /// Hand the sheet a closure that does the call. The screen does not know how
  /// to reach a provider and should not: it knows how to ask.
  Future<void> _askAi() async {
    final Future<PlanRewrite> Function(String)? run = widget.onRewritePlan;
    if (run == null) return;

    final ReadingPlan? next = await PlanRewriteSheet.show(
      context,
      plan: m.plan,
      run: run,
      whoReads: m.writer.name,
      endpointLine: m.writerBase,
    );
    if (next == null || !mounted) return;
    widget.onPlanChanged(next);
    Toast.show(context, 'plan saved · nothing is written until you tap Write it');
  }

  String _valueOf(ReadingPlan p, PlanField f) => switch (f) {
        PlanField.reader => p.reader.isEmpty ? 'not set' : p.reader,
        PlanField.style => p.style.isEmpty ? 'not set' : p.style.join(' · '),
        PlanField.gloss => p.gloss.isEmpty ? 'not set' : p.gloss.join(' · '),
        PlanField.avoid => p.avoid.isEmpty ? 'not set' : p.avoid.join(' · '),
        PlanField.lengthShort => 'about ${p.shortWords} words',
        PlanField.lengthMedium => 'about ${p.mediumWords} words',
        PlanField.lengthLong => 'about ${p.longWords} words',
      };

  /// One plan field. Tappable — "edit" is a word, and a word that does nothing is
  /// worse than no word at all, so the whole row is the button.
  Widget _FieldRow({
    required PlanField field,
    required String value,
    required VoidCallback onTap,
  }) {
    final Palette c = context.colors;
    final bool empty = value == 'not set' || value == 'any topic';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 13, bottom: 3),
              child: Row(
                children: <Widget>[
                  Text(
                    field.label.toUpperCase(),
                    style: TextStyle(
                      fontFamily: TypeScale.mono,
                      fontSize: 10,
                      letterSpacing: 0.14,
                      color: empty ? c.ink3 : c.verm,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'edit',
                    style: TextStyle(
                      fontFamily: TypeScale.sans,
                      fontSize: 11,
                      color: c.ink3,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 14.5,
                height: 1.55,
                color: empty ? c.ink3 : c.ink,
              ),
            ),
            Hairline(color: c.hair),
          ],
        ),
      ),
    );
  }

  /// The reader's own words. Sent VERBATIM on top of the structured fields, and
  /// never dropped by an edit elsewhere — DESIGN is explicit that Ask-the-AI
  /// edits fields, it does not eat this.
  Future<void> _editRaw() async {
    final String? v = await TextPromptSheet.ask(
      context,
      title: 'My own words',
      hint: 'Anything a field cannot hold',
      note: 'Sent to the writer exactly as written, on top of every field '
          'above. Editing a field never eats this.',
      initial: m.plan.raw,
    );
    if (v == null || !mounted) return;
    widget.onPlanChanged(m.plan.copyWith(raw: v));
    Toast.show(context, 'saved · the writer reads it exactly as written');
  }

  /// Which band a length row edits. Total by construction: every member of
  /// `PlanField.lengths` maps to a band, and the throw is unreachable.
  static LengthBand _bandOf(PlanField f) => switch (f) {
        PlanField.lengthShort => LengthBand.short,
        PlanField.lengthMedium => LengthBand.medium,
        PlanField.lengthLong => LengthBand.long,
        _ => throw ArgumentError('$f is not a length field'),
      };

  /// Edit one field. Numbers get a stepper, lists get a chip picker, and the
  /// reader's own words get a plain text box — because those are three different
  /// kinds of value and one generic text field would be wrong twice.
  Future<void> _editField(PlanField field) async {
    final ReadingPlan p = m.plan;
    ReadingPlan next = p;

    switch (field) {
      case PlanField.reader:
        final String? v = await TextPromptSheet.ask(
          context,
          title: 'Reader',
          hint: 'software developer, comfortable with code, new to finance '
              'English',
          note: 'This is the vocabulary ceiling: it tells the writer how much '
              'it may assume.',
        );
        if (v == null) return;
        next = p.copyWith(reader: v);
        break;

      case PlanField.style:
        final List<String>? v = await ChipPickerSheet.ask(
          context,
          title: 'Style',
          note: 'How it should read.',
          initial: p.style,
          presets: const <String>[
            'start with the thing itself',
            'short sentences',
            'say it once',
            'no headings',
            'concrete examples',
          ],
        );
        if (v == null) return;
        next = p.copyWith(style: v);
        break;

      case PlanField.gloss:
        final List<String>? v = await ChipPickerSheet.ask(
          context,
          title: 'Explain',
          note: 'Which words get the plain-language treatment.',
          initial: p.gloss,
          presets: const <String>[
            'finance words',
            'anything where a wrong guess would be embarrassing',
            'anything with more than one meaning in this article',
          ],
        );
        if (v == null) return;
        next = p.copyWith(gloss: v);
        break;

      case PlanField.avoid:
        final List<String>? v = await ChipPickerSheet.ask(
          context,
          title: 'Avoid',
          note: 'The negative space. This is the one field that can stop a '
              'fluent-but-wrong draft.',
          initial: p.avoid,
          presets: const <String>[
            'background before the point',
            'anything I already know',
            'rhetorical questions',
            'a summary at the end',
          ],
        );
        if (v == null) return;
        next = p.copyWith(avoid: v);
        break;

      // The three bands are the SAME editor with different values, so they are
      // one case rather than three. `_bandOf` is what keeps them from being
      // three copies of one dialog that drift apart.
      case PlanField.lengthShort:
      case PlanField.lengthMedium:
      case PlanField.lengthLong:
        final LengthBand band = _bandOf(field);
        final int? v = await NumberStepSheet.ask(
          context,
          title: '${band.label} article',
          note: 'About how many words. The writer aims at this; it is not a '
              'hard cut, and a piece that lands at 290 instead of 300 is not a '
              'failure.',
          value: p.wordsFor(band),
          min: 50,
          max: 2000,
          step: 25,
          suffix: 'words',
        );
        if (v == null) return;
        next = switch (band) {
          LengthBand.short => p.copyWith(shortWords: v),
          LengthBand.medium => p.copyWith(mediumWords: v),
          LengthBand.long => p.copyWith(longWords: v),
          LengthBand.custom => p,
        };
        break;
    }

    if (!mounted) return;
    widget.onPlanChanged(next);
    Toast.show(context, 'saved · nothing is written until you tap Write it');
  }

  // ── Voice ─────────────────────────────────────────────────────────────

  Widget _voice(Palette c) {
    final bool device = m.voiceSource == 'device';
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 18, Gap.gutter, 30),
      children: <Widget>[
        Text('Voice', style: context.texts.titleLarge),
        const SizedBox(height: 4),
        Text(
          "Two engines. The phone's own needs nothing and works offline; MiMo "
          'is the only online one.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.6,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 18),
        _Choice(
          title: 'On-device only',
          sub: m.deviceVoice.available
              ? 'the engine already on your phone · airplane mode · \$0.00'
              : 'selected, but ${m.deviceVoice.note}',
          selected: device,
          onTap: () => widget.onVoiceSelected('device'),
        ),
        const SizedBox(height: 8),
        _Choice(
          title: 'Xiaomi MiMo',
          sub: VoiceEndpoint.mimo.costLine,
          selected: !device,
          onTap: () => widget.onVoiceSelected('mimo'),
        ),
        if (!device) ...<Widget>[
          const SizedBox(height: 18),
          const SectionLabel('MiMo connection'),
          _TapRow(
            label: 'Base URL',
            value: m.voiceBase,
            onTap: _editVoiceBase,
          ),
          _TapRow(
            label: 'API key',
            value: m.voiceKeySaved
                ? 'a key is saved in this phone'
                : 'not set — MiMo cannot be used yet',
            onTap: _editVoiceKey,
          ),
          _TapRow(
            label: 'Voice',
            value: m.voiceName,
            onTap: _editVoiceName,
          ),
          const SizedBox(height: 12),
          Btn(
            label: _working ? 'Asking…' : 'Play one word to test it',
            primary: false,
            onPressed: _working ? null : () => _probeVoice(),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.paperSunk,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.hair),
          ),
          child: Text(
            device
                ? 'No article audio is pre-built. You read in silence and tap '
                    'words; every single word still has sound, for free, in '
                    'airplane mode.'
                : 'A recorded voice is fetched once per sentence and kept on '
                    'this phone, so hearing it again costs nothing and works '
                    'offline. With no key the app says so and falls back to the '
                    "phone's own voice rather than going quiet.",
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13,
              height: 1.65,
              color: c.ink2,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editVoiceBase() async {
    final String? v = await TextPromptSheet.ask(
      context,
      title: 'Base URL',
      hint: VoiceEndpoint.mimo.baseUrl,
      note: 'The address requests go to, and the only address your key is ever '
          'sent to. Change it only if your provider gave you a different one.',
      initial: m.voiceBase,
      mono: true,
      saveLabel: 'Save',
    );
    if (v == null || v.trim().isEmpty || !mounted) return;
    widget.onVoiceBaseChanged(v.trim());
  }

  Future<void> _editVoiceKey() async {
    final String? v = await TextPromptSheet.ask(
      context,
      title: 'MiMo API key',
      hint: 'paste the key',
      note: "Stored in this phone's keystore and only ever sent to the address "
          'above. There is no server in this version, so there is nothing that '
          'could see it.',
      obscure: true,
      saveLabel: 'Save it on this phone',
    );
    if (v == null || v.trim().isEmpty || !mounted) return;
    widget.onVoiceKeyChanged(v.trim());
  }

  Future<void> _editVoiceName() async {
    // Not `const`: a property read off a const object is not itself a constant
    // expression, so this has to be a final.
    //
    // `Random` is first and is a MODE, not an id: it rolls one of the real
    // voices for each ARTICLE. A reader who wants variety without choosing is
    // exactly the person this option is for. One article keeps one narrator —
    // rolling per sentence would make the piece unlistenable.
    final List<String> names = voiceChoices();
    final List<String>? v = await ChipPickerSheet.ask(
      context,
      title: 'Voice',
      note: 'MiMo publishes no list to fetch, so these are the built-in names. '
          'One of them speaks a word and you hear whether you like it. '
          'Random picks one narrator per article, and keeps it for that whole '
          'piece.',
      initial: <String>[m.voiceName],
      presets: names,
    );
    if (v == null || v.isEmpty || !mounted) return;
    widget.onVoiceNameChanged(v.first);
  }

  Future<void> _probeVoice() async {
    setState(() => _working = true);
    // `finally`, not a plain await-then-reset. Every one of these calls reaches
    // the keystore and the network, and either can throw something the caller
    // did not anticipate; without the finally that throw left the button
    // reading "Asking…" for the rest of the session, which is a worse failure
    // than the one it was reporting.
    String? problem;
    try {
      problem = await widget.onProbeVoice();
    } catch (e) {
      problem = 'the test could not run · $e';
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (!mounted) return;
    Toast.show(
      context,
      problem ?? 'that voice spoke · it is now the one this app uses',
      duration: const Duration(milliseconds: 3200),
    );
  }

  // ── Listening: whether it starts itself, and what happens next ────────
  //
  // Voice picks the ENGINE; this pane picks the BEHAVIOUR — and the two are
  // separate rows on the hub because a reader who wants the phone's free
  // offline voice has no reason to open a pane about MiMo keys just to stop
  // the screen from talking the moment it opens.

  /// The read-only summary of the player's "when it ends" chips. The writable
  /// control is on the Listen screen; this pane only states what is set.
  static String _endModeSummary(String mode, int count) => switch (mode) {
        'forever' =>
          'Keep going — the next article starts, and the next, until the queue ends.',
        'count' =>
          'Keep going a few more — $count more articles, then it stops.',
        'loop' =>
          'Loop this — the current article plays again from the top, forever.',
        _ => 'Stop — nothing further plays until you ask.',
      };

  Widget _listening(Palette c) {
    final String mode = m.listenAutoContinue;
    final int count = m.listenAutoContinueCount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 18, Gap.gutter, 30),
      children: <Widget>[
        Text('Listening', style: context.texts.titleLarge),
        const SizedBox(height: 4),
        Text(
          'What the listening screen does on its own. Every default here is '
          'the quiet one — nothing starts, nothing continues, newest first.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.6,
            color: c.ink3,
          ),
        ),

        const SizedBox(height: 20),
        const SectionLabel('Start playing when I open Listen'),
        Text(
          'The default waits for a tap. A screen that talks first surprises '
          'people in quiet places — a library, a late train, a shared desk — '
          'and the tap it costs to start is small.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.6,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 12),
        _Choice(
          title: 'Wait for me to tap Play',
          sub: 'silent until you ask — the default',
          selected: !m.listenAutoPlay,
          onTap: () => widget.onListenAutoPlay(false),
        ),
        const SizedBox(height: 8),
        _Choice(
          title: 'Play at once',
          sub: 'sound starts the moment the screen opens',
          selected: m.listenAutoPlay,
          onTap: () => widget.onListenAutoPlay(true),
        ),

        const SizedBox(height: 22),
        const SectionLabel('When one article ends'),
        // Read-only on purpose. This is a play-mode decision the listener flips
        // mid-commute, so the writable control lives on the player, next to the
        // transport — and there is exactly one place that can change it, which
        // is the only way two surfaces cannot drift apart.
        Text(
          _endModeSummary(mode, count),
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.6,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Change it on the Listen screen, under the play button.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 12.5,
            height: 1.6,
            color: c.ink3,
          ),
        ),

        const SizedBox(height: 22),
        const SectionLabel('Pick the next one by'),
        for (final (String value, String title, String sub)
            in <(String, String, String)>[
              (
                'newest',
                'Newest first',
                'the card that arrived most recently',
              ),
              ('oldest', 'Oldest first', 'the card that has waited longest'),
              (
                'mostStudied',
                'Most studied',
                'what you have met most — review first',
              ),
              (
                'leastStudied',
                'Least studied',
                'what you have met least — fresh first',
              ),
              ('random', 'Random, not today\'s', 'a shuffle, with one exception'),
            ]) ...<Widget>[
          _Choice(
            title: title,
            sub: sub,
            selected: m.listenAutoOrder == value,
            onTap: () => widget.onListenAutoOrder(value),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          'Random avoids an article already heard today when anything else '
          'exists — the repeat is the one that gets skipped.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 12.5,
            height: 1.6,
            color: c.ink3,
          ),
        ),
      ],
    );
  }

  // ── Who writes ────────────────────────────────────────────────────────

  Widget _writer(Palette c) {
    final WriterEndpoint ep = m.writer;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 18, Gap.gutter, 30),
      children: <Widget>[
        Text('Who writes', style: context.texts.titleLarge),
        const SizedBox(height: 4),
        Text(
          'A list of access points, not one choice. Switching is free and '
          'rewrites nothing already written.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.6,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 18),
        for (final WriterEndpoint e in WriterEndpoint.all) ...<Widget>[
          _Choice(
            title: e.name,
            // Vision is stated on the row, not discovered by failing. A reader
            // who wants to write an article from a photograph of a word list
            // needs to know WHICH endpoint takes one before they take the
            // picture — and a toast that says "unsupported" after they have
            // chosen is a toast that arrives too late to help.
            sub: e.supportsVision
                ? '${e.costLine} · sees pictures'
                : '${e.costLine} · text only',
            selected: e.id == m.writerId,
            onTap: () => widget.onWriterSelected(e.id),
          ),
          const SizedBox(height: 8),
        ],
        const SectionLabel('Connection'),
        _TapRow(
          label: 'Base URL',
          value: m.writerBase,
          onTap: () => _editWriterBase(ep),
        ),
        _TapRow(
          label: 'API key',
          value: m.writerKeySaved
              ? 'a key is saved in this phone'
              : 'not set — writing stays switched off',
          onTap: _editWriterKey,
        ),
        const SizedBox(height: 12),
        Btn(
          label: _working ? 'Asking…' : 'Test the key',
          primary: false,
          onPressed: _working || !m.writerKeySaved
              ? null
              : () => _testWriter(ep),
        ),
        const SizedBox(height: 6),
        Text(
          m.writerKeySaved
              ? 'A test is one short request that costs a fraction of a cent '
                  'and writes nothing.'
              : 'Save a key first. The test button stays out of the way until '
                  'there is something to test.',
          style: TextStyle(
            fontFamily: TypeScale.sans,
            fontSize: 11.5,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.paperSunk,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.hair),
          ),
          child: Text(
            "Your key is stored in this phone's own keystore and only ever goes "
            'to the address above. There is no server: this version does not '
            'sell a service, so there is nothing to sell your key to.',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13,
              height: 1.65,
              color: c.ink2,
            ),
          ),
        ),

        // ── the two optional sources ────────────────────────────────────
        //
        // Both are OPTIONAL in the strongest sense the app has: with neither
        // configured the writer still writes, and the cost line on a card still
        // says one call. What they buy is research — the writer gets to look
        // something up before it starts.
        const SizedBox(height: 26),
        Hairline(color: c.hair),
        const SizedBox(height: 18),
        const SectionLabel('Sources the writer may consult'),
        Text(
          'Optional, both of them. With neither set the writer works from what '
          'it already knows, in one call. With one set it can read before it '
          'writes, which costs a little more and takes a little longer — and '
          'the card says so before you tap.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.65,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 16),

        _sourceCard(
          c,
          title: 'Zhihu Daily',
          body: 'A daily list of thirty stories. The writer may pick one and '
              'read it, then write its own English article about the subject — '
              'not a translation of it.',
          keySaved: m.newsKeySaved,
          on: m.newsOn,
          onToggle: widget.onNewsToggled,
          onEditKey: _editNewsKey,
          onTest: _testNews,
          testLabel: 'Test the key',
          costLine: 'uapis.cn · one request for the list, one per story read',
        ),
        const SizedBox(height: 14),
        _sourceCard(
          c,
          title: 'Web search',
          body: 'Alibaba Cloud\'s search, reached over MCP. The writer may '
              'search for a fact it is unsure of. It is told not to search for '
              'the sake of looking busy — every search is another call.',
          keySaved: m.searchKeySaved,
          on: m.searchOn,
          onToggle: widget.onSearchToggled,
          onEditKey: _editSearchKey,
          onTest: _testSearch,
          testLabel: 'Test the key',
          costLine: 'dashscope.aliyuncs.com · one search per lookup',
        ),
      ],
    );
  }

  /// One optional source: what it is, whether a key is saved, a switch, and a
  /// test that proves the key works.
  ///
  /// The switch is DISABLED with no key rather than hidden — a control that
  /// vanishes teaches the reader nothing, while a greyed one beside the words
  /// "no key saved" answers the question they were about to ask.
  Widget _sourceCard(
    Palette c, {
    required String title,
    required String body,
    required bool keySaved,
    required bool on,
    required ValueChanged<bool> onToggle,
    required VoidCallback onEditKey,
    required Future<void> Function() onTest,
    required String testLabel,
    required String costLine,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.cardAll,
        border: Border.all(color: c.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: TypeScale.sans,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
              // The state in words next to the switch, because a switch alone
              // says what will happen and not whether it can.
              Text(
                keySaved ? (on ? 'on' : 'off') : 'no key',
                style: TextStyle(
                  fontFamily: TypeScale.mono,
                  fontSize: 10.5,
                  color: keySaved ? (on ? c.jade : c.ink3) : c.ink3,
                ),
              ),
              const SizedBox(width: 6),
              Switch(
                value: keySaved && on,
                onChanged: keySaved ? onToggle : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 12.5,
              height: 1.65,
              color: c.ink3,
            ),
          ),
          const SizedBox(height: 10),
          _TapRow(
            label: 'API key',
            value: keySaved ? 'a key is saved in this phone' : 'not set',
            onTap: onEditKey,
          ),
          const SizedBox(height: 8),
          // Stacked, not side by side. `Btn` is full-width BY DESIGN — its
          // build is a `SizedBox(width: double.infinity)` — so putting it in a
          // Row hands it unbounded width, which is a layout error. In a release
          // build that error paints as a large blank box instead of a red one,
          // which is how it got as far as a screenshot: two cards, each with a
          // screenful of nothing under the text.
          Btn(
            label: _working ? 'Asking…' : testLabel,
            primary: false,
            dense: true,
            onPressed: _working || !keySaved ? null : onTest,
          ),
          const SizedBox(height: 7),
          Text(
            costLine,
            style: TextStyle(
              fontFamily: TypeScale.mono,
              fontSize: 9.5,
              height: 1.4,
              color: c.ink3,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editNewsKey() async {
    final String? v = await TextPromptSheet.ask(
      context,
      title: 'Zhihu Daily key',
      hint: 'paste the uapis.cn key',
      note: 'Optional. Stored in this phone\'s keystore, sent only to '
          'uapis.cn. Saving it switches the source on.',
      obscure: true,
      saveLabel: 'Save it on this phone',
    );
    if (v == null || v.trim().isEmpty || !mounted) return;
    widget.onNewsKeyChanged(v.trim());
  }

  Future<void> _editSearchKey() async {
    final String? v = await TextPromptSheet.ask(
      context,
      title: 'Web search key',
      hint: 'paste the Alibaba Cloud key',
      note: 'Optional. Stored in this phone\'s keystore, sent only to '
          'dashscope.aliyuncs.com. Saving it switches the source on.',
      obscure: true,
      saveLabel: 'Save it on this phone',
    );
    if (v == null || v.trim().isEmpty || !mounted) return;
    widget.onSearchKeyChanged(v.trim());
  }

  /// Both tests go through the same "one tap, one sentence" shape as the
  /// writer test: the pane shows "Asking…", the button refuses a second press,
  /// and a thrown error becomes a sentence rather than a stuck button.
  Future<void> _runProbe(Future<String?> Function() run, String ok) async {
    setState(() => _working = true);
    String? problem;
    try {
      problem = await run();
    } catch (e) {
      problem = 'the test could not run · $e';
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (!mounted) return;
    Toast.show(
      context,
      problem ?? ok,
      duration: const Duration(milliseconds: 3200),
    );
  }

  Future<void> _testNews() => _runProbe(
        widget.onTestNews,
        'the news source answered. Nothing was written.',
      );

  Future<void> _testSearch() => _runProbe(
        widget.onTestSearch,
        'the search source answered. Nothing was written.',
      );

  Future<void> _editWriterBase(WriterEndpoint ep) async {
    final String? v = await TextPromptSheet.ask(
      context,
      title: 'Base URL',
      hint: ep.baseUrl,
      note: 'Where article-writing requests go, and the only address the key '
          'is ever sent to.',
      initial: m.writerBase,
      mono: true,
    );
    if (v == null || v.trim().isEmpty || !mounted) return;
    widget.onWriterBaseChanged(v.trim());
  }

  Future<void> _editWriterKey() async {
    final String? v = await TextPromptSheet.ask(
      context,
      title: 'API key',
      hint: 'paste the key',
      note: "Stored in this phone's keystore. Writing only ever happens when "
          'you tap Write it on a card — nothing is generated on its own, ever.',
      obscure: true,
      saveLabel: 'Save it on this phone',
    );
    if (v == null || v.trim().isEmpty || !mounted) return;
    widget.onWriterKeyChanged(v.trim());
  }

  Future<void> _testWriter(WriterEndpoint ep) async {
    setState(() => _working = true);
    // See _probeVoice: the finally is what keeps a thrown keystore or socket
    // error from pinning the button at "Asking…".
    String? problem;
    try {
      problem = await widget.onTestWriter();
    } catch (e) {
      problem = 'the test could not run · $e';
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (!mounted) return;
    Toast.show(
      context,
      problem ?? '${ep.name} answered. Nothing was written.',
      duration: const Duration(milliseconds: 3200),
    );
  }

  // ── Instructions: the sentences you keep ──────────────────────────────

  /// The collection, or null while it is being read.
  List<Instruction>? _saved;

  /// The search box. Plain state + a local `.where()`, the same shape the
  /// library screen uses — `SearchAnchor` brings a whole Material search
  /// experience (suggestions, a full-screen view) that this list does not want.
  final TextEditingController _search = TextEditingController();

  Future<void> _loadInstructions() async {
    try {
      final List<Instruction> all = await widget.onLoadInstructions();
      if (!mounted) return;
      setState(() {
        _saved = all;
        _instructionCount = all.length;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saved = <Instruction>[]);
      Toast.show(context, 'the saved instructions could not be read · $e');
    }
  }

  Widget _instructions(Palette c) {
    final List<Instruction>? all = _saved;
    final String q = _search.text.trim().toLowerCase();
    final List<Instruction> shown = all == null
        ? const <Instruction>[]
        : (q.isEmpty
            ? all
            : all
                .where((Instruction i) => i.text.toLowerCase().contains(q))
                .toList());

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 18, Gap.gutter, 30),
      children: <Widget>[
        Text('Instructions', style: context.texts.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Things you have asked for, in your own words. An instruction is not '
          'a subject label — it is a sentence, and the writer follows it. '
          'Articles you never touch are not affected by any of this: with '
          'nothing chosen, the writer picks the subject itself.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.65,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 16),
        Btn(
          label: '✎ Write a new one',
          primary: true,
          onPressed: _newInstruction,
        ),

        if (all == null) ...<Widget>[
          const SizedBox(height: 24),
          Text(
            'reading…',
            style: TextStyle(
              fontFamily: TypeScale.mono,
              fontSize: 11.5,
              color: c.ink3,
            ),
          ),
        ] else if (all.isEmpty) ...<Widget>[
          const SizedBox(height: 24),
          _emptyBox(
            c,
            'Nothing saved yet',
            'An instruction is for the times you want something particular — '
            '"explain how a limit order fills, for someone who has never '
            'traded", or "a short story about a lighthouse keeper". Write one '
            'and it will be offered on every card you change.',
          ),
        ] else ...<Widget>[
          const SizedBox(height: 18),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 14.5,
              color: c.ink,
            ),
            decoration: InputDecoration(
              hintText: 'search your instructions',
              hintStyle: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 14,
                color: c.ink3,
              ),
              isDense: true,
              filled: true,
              fillColor: c.paperSunk,
              prefixIcon: Icon(Icons.search, size: 18, color: c.ink3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(color: c.hair),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(color: c.hair),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide(color: c.verm),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),
          if (shown.isEmpty)
            Text(
              'Nothing matches “${_search.text.trim()}”.',
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 13.5,
                color: c.ink3,
              ),
            )
          else
            for (final Instruction i in shown) ...<Widget>[
              _instructionRow(c, i),
              const SizedBox(height: 8),
            ],
        ],

        const SizedBox(height: 22),
        Hairline(color: c.hair),
        const SizedBox(height: 14),
        Text(
          'Saved instructions live on this phone, in the same database as '
          'everything else. Deleting one never touches an article that was '
          'already written from it.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 12.5,
            height: 1.65,
            color: c.ink3,
          ),
        ),
      ],
    );
  }

  Widget _instructionRow(Palette c, Instruction i) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 8, 11),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.cardAll,
        border: Border.all(color: c.hair),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  i.text,
                  style: TextStyle(
                    fontFamily: TypeScale.serif,
                    fontSize: 14.5,
                    height: 1.5,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 5),
                // The counts are the reason this list is worth keeping: an
                // instruction used four times is one the reader likes, and one
                // used never is one they are about to delete.
                Text(
                  i.useCount == 0
                      ? 'never used · saved ${_ago(i.createdDay)}'
                      : 'used ${i.useCount}× · last ${_ago(i.sortDay)}',
                  style: TextStyle(
                    fontFamily: TypeScale.mono,
                    fontSize: 10,
                    color: c.ink3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _MiniAction(label: 'Edit', onTap: () => _editInstruction(i)),
          const SizedBox(width: 4),
          _MiniAction(label: 'Delete', onTap: () => _deleteInstruction(i)),
        ],
      ),
    );
  }

  Future<void> _newInstruction() async {
    final String? text = await TextPromptSheet.ask(
      context,
      title: 'What should be written?',
      hint: 'a sentence, not a word',
      note: 'The writer follows this exactly. Anything you do not fill in '
          'yourself stays the writer\'s choice.',
      saveLabel: 'Save it',
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    final String? problem = await widget.onSaveInstruction(text.trim());
    if (!mounted) return;
    if (problem != null) {
      Toast.show(context, problem);
      return;
    }
    await _loadInstructions();
    if (!mounted) return;
    Toast.show(context, 'saved · pick it when you change a card');
  }

  Future<void> _editInstruction(Instruction i) async {
    final String? text = await TextPromptSheet.ask(
      context,
      title: 'Edit this instruction',
      hint: 'a sentence, not a word',
      note: 'Articles already written are not affected. This changes what the '
          'writer does the next time you pick it.',
      initial: i.text,
      saveLabel: 'Save it',
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    final String? problem =
        await widget.onSaveInstruction(text.trim(), id: i.id);
    if (!mounted) return;
    if (problem != null) {
      Toast.show(context, problem);
      return;
    }
    await _loadInstructions();
    if (!mounted) return;
    Toast.show(context, 'updated');
  }

  /// Deleting asks first, in the app's own sheet rather than a Material
  /// `AlertDialog` — there is not one `AlertDialog` in this codebase, and a
  /// confirmation that looks different from every other sheet is a confirmation
  /// the reader has to read twice.
  Future<void> _deleteInstruction(Instruction i) async {
    final bool? yes = await AppSheet.show<bool>(
      context,
      builder: (BuildContext ctx) => _ConfirmDelete(text: i.text),
    );
    if (yes != true || !mounted) return;
    final String? problem = await widget.onDeleteInstruction(i.id);
    if (!mounted) return;
    if (problem != null) {
      Toast.show(context, problem);
      return;
    }
    await _loadInstructions();
    if (!mounted) return;
    Toast.show(context, 'deleted · articles already written are untouched');
  }

  // ── Appearance: three surfaces, six faces ─────────────────────────────

  Widget _appearance(Palette c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 18, Gap.gutter, 30),
      children: <Widget>[
        Text('Appearance', style: context.texts.titleLarge),
        const SizedBox(height: 4),
        Text(
          'How the app looks. Nothing here changes with the clock — the only '
          'thing that can change the surface on its own is the phone\'s own '
          'setting, and only because you asked it to.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.6,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 20),

        const SectionLabel('Surface'),
        for (final AppearanceMode a in AppearanceMode.values) ...<Widget>[
          _Choice(
            title: a.label,
            sub: switch (a) {
              AppearanceMode.light => 'warm paper · the default surface',
              AppearanceMode.dark => 'warm ink · low glare',
              AppearanceMode.system =>
                'light or dark, whichever the phone is set to',
            },
            selected: m.appearance == a,
            onTap: () => widget.onAppearance(a),
          ),
          const SizedBox(height: 8),
        ],

        const SizedBox(height: 20),
        const SectionLabel('Reading typeface'),
        Text(
          'The face an ARTICLE is set in. Buttons, labels and data rows keep '
          'their own three families — that split is not a matter of taste.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.6,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 12),
        for (final ReadingFace f in ReadingFace.values) ...<Widget>[
          _FaceChoice(
            face: f,
            selected: m.face == f,
            onTap: () => widget.onFace(f),
          ),
          const SizedBox(height: 8),
        ],

        const SizedBox(height: 12),
        Text(
          'Every article here is bilingual, so a face is only good if the '
          'Chinese beside it looks right — and that is decided by what the '
          'phone substitutes for the characters a Latin font does not have. '
          'The first two options are the phone\'s own families, which is why '
          'their Chinese matches. A bundled Latin font has no Chinese at all, '
          'so its Chinese falls back to the phone\'s sans.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 12.5,
            height: 1.65,
            color: c.ink3,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Text size is set on the reading and listening screens themselves, '
          'in their own toolbars. It is not repeated here.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 12.5,
            height: 1.65,
            color: c.ink3,
          ),
        ),
      ],
    );
  }

  // ── The small print: the dictionary, and what the app will not do ──────

  Widget _smallPrint(Palette c) {
    final int entries = m.dictionaryEntries;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 18, Gap.gutter, 30),
      children: <Widget>[
        Text('The small print', style: context.texts.titleLarge),
        const SizedBox(height: 18),
        const SectionLabel('Dictionary'),
        Text(
          entries == 0
              ? 'inflating on first run…'
              : '${_commas(entries)} words · offline · \$0.00 · never a network call',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 14.5,
            height: 1.55,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'A word this dictionary does not carry is reported as missing rather '
              'than looked up somewhere. That is the whole trade: \$0.00, '
              'airplane mode, and an honest "not in there".',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.65,
            color: c.ink3,
          ),
        ),
        // The difficulty label is the one number in this app that looks like a
        // verdict, so the caveats travel with it rather than sitting in a doc
        // nobody opens. Everything below is from the coverage literature.
        const SectionLabel('What "Easy" and "Hard" mean'),
        Text(
          'A card is labelled from the share of its words that carry a mark — '
          'Easy at 2% or less (about 1 word in 50), Medium up to 5% (1 in 20), '
          'Hard beyond that. Both counts are running words, so a word you do '
          'not know costs one every time it appears, not once.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.65,
            color: c.ink2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Three things it does not mean. The 2% and 5% lines are conventions '
          'from vocabulary research, not cliffs: Schmitt, Jiang and Grabe '
          '(2011) tested 661 readers and found a linear relationship with "no '
          'indication of a vocabulary threshold", and Webb, Pellicer-Sánchez '
          'and Wang (2025) could not replicate a threshold effect at all. The '
          'same study found readers at 100% coverage scoring 7 out of 30, so '
          'the label says nothing about you. And the words marked are the '
          'words a WRITER thought would be hard — not the words you actually '
          'do not know.',
          style: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 13,
            height: 1.65,
            color: c.ink3,
          ),
        ),
        const SectionLabel('What this app will not do'),
        for (final String line in const <String>[
          'ask whether you remember a word',
          'give you a streak, a score, or a percentage',
          'delete anything you read — freeing space only removes the file',
          'schedule anything, or write on its own',
          'look a word up over the network',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('·', style: TextStyle(color: c.verm, fontSize: 15)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line,
                    style: TextStyle(
                      fontFamily: TypeScale.serif,
                      fontSize: 13.5,
                      height: 1.55,
                      color: c.ink2,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _commas(int v) =>
      v.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (Match m) => '${m[1]},');

  /// A boxed paragraph, for the states that are not a list: empty, and
  /// "nothing matched".
  Widget _emptyBox(Palette c, String title, String body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: c.paperSunk,
        borderRadius: Radii.cardAll,
        border: Border.all(color: c.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13,
              height: 1.65,
              color: c.ink3,
            ),
          ),
        ],
      ),
    );
  }

  /// `YYYY-MM-DD` → "today" / "yesterday" / "12 days ago".
  ///
  /// Day strings, not timestamps: the app counts reads by day, and a relative
  /// date computed from anything finer would be a different kind of fact from
  /// the one stored.
  static String _ago(String day) {
    final DateTime? then = DateTime.tryParse(day);
    if (then == null) return day;
    final DateTime now = DateTime.now();
    final int days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(then.year, then.month, then.day))
        .inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 30) return '$days days ago';
    final int months = days ~/ 30;
    return months == 1 ? 'a month ago' : '$months months ago';
  }
}

/// The restore confirmation.
class _ConfirmRestore extends StatelessWidget {
  const _ConfirmRestore();

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sheetPad, 0, Gap.sheetPad, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Restore the defaults?',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'All seven fields go back to what a fresh install has — including '
            'the three lengths, which return to $kShortWords / $kMediumWords / '
            '$kLongWords. Anything you wrote in your own words is cleared.',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13.5,
              height: 1.65,
              color: c.ink3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'There is no undo, and articles already written are not touched.',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13.5,
              height: 1.65,
              color: c.ink3,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: Btn(
                  label: 'Keep my plan',
                  primary: false,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Btn(
                  label: 'Restore',
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

/// A small flat text button for a row's trailing actions.
class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: TypeScale.sans,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.verm,
            ),
          ),
        ),
      ),
    );
  }
}

/// The delete confirmation for an instruction.
class _ConfirmDelete extends StatelessWidget {
  const _ConfirmDelete({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sheetPad, 0, Gap.sheetPad, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Delete this instruction?',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: c.paperSunk,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.hair),
            ),
            child: Text(
              text,
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 14,
                height: 1.5,
                color: c.ink2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Articles already written from it are not touched. This only '
            'removes it from the list you pick from.',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13,
              height: 1.6,
              color: c.ink3,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: Btn(
                  label: 'Keep it',
                  // NOT primary. `Btn` defaults to the filled vermilion face,
                  // so the safe option was rendering as loudly as the
                  // destructive one — two red buttons side by side, which is
                  // both the second emphasis the design forbids and a real
                  // hazard on a confirmation whose other half deletes.
                  primary: false,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Btn(
                  label: 'Delete',
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

/// A label/value row that is also the button that changes it.
class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 13, bottom: 3),
              child: Row(
                children: <Widget>[
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontFamily: TypeScale.mono,
                      fontSize: 10,
                      letterSpacing: 0.14,
                      color: c.ink3,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'edit',
                    style: TextStyle(
                      fontFamily: TypeScale.sans,
                      fontSize: 11,
                      color: c.ink3,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontFamily: TypeScale.mono,
                fontSize: 12.5,
                height: 1.5,
                color: c.ink,
              ),
            ),
            Hairline(color: c.hair),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Material(
      color: selected ? c.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? c.verm : c.hair),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
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
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
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
              if (selected) ...<Widget>[
                const SizedBox(width: 8),
                Icon(Icons.check, size: 16, color: c.verm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One reading face, shown IN that face.
///
/// The preview is not decoration and it is not only English. A reader choosing
/// a typeface is choosing how a bilingual page will look, and the half that is
/// hardest to get right is the half no Latin font contains — so the sample is
/// an English sentence with its Chinese underneath, set exactly as an article
/// would be. Picking from a list of names would be picking blind.
class _FaceChoice extends StatelessWidget {
  const _FaceChoice({
    required this.face,
    required this.selected,
    required this.onTap,
  });

  final ReadingFace face;
  final bool selected;
  final VoidCallback onTap;

  /// The sentence the sample is drawn from. Short, and one whose Chinese is
  /// unambiguous — a preview that reads oddly makes the FACE look wrong.
  static const String _english = 'A pointer is just a number.';
  static const String _chinese = '指针不过是一个数字。';

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Material(
      color: selected ? c.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? c.verm : c.hair),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      face.label,
                      // The name is set in the face itself: at 15px it is
                      // already a preview, and a reader scrolling the list sees
                      // every option before reading a single note.
                      style: face.style(c.ink, 15),
                    ),
                  ),
                  if (selected) Icon(Icons.check, size: 16, color: c.verm),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _english,
                style: face.style(c.ink, 16, height: 1.5),
              ),
              Text(
                _chinese,
                style: face.style(c.ink2, 13.5, height: 1.6),
              ),
              const SizedBox(height: 6),
              Text(
                face.note,
                style: TextStyle(
                  fontFamily: TypeScale.serif,
                  fontSize: 12.5,
                  height: 1.55,
                  color: c.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}