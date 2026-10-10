// "Ask the AI to change it" — the plan, edited by the model that writes from it.
//
// The domain half of this has existed since the beginning and was never wired
// to anything: `PlanRewrite` holds a proposal and a per-field diff, and refuses
// to be applied once the request it describes has changed. This file is the
// other half.
//
// Two rules shape the whole sheet.
//
// **Nothing is applied until the reader says so.** The answer is a DIFF, shown
// field by field with the old value struck through. "Your plan changed" is a
// claim, and a claim you cannot see is the same failure as a tapped word that
// shows its Chinese before its English. The diff is also the way IN: each
// proposed value can be corrected in place, and `Use this plan` applies the
// proposal AS ADJUSTED — a generated template you can only accept wholesale is
// not a template, it is a verdict.
//
// **A paid-for answer cannot be thrown away by a stray tap.** While an
// unaccepted diff is on screen the sheet is LOCKED: the scrim will not dismiss
// it, the drag is off, and the one Close says why instead of closing. Editing
// the request is the way out, and it is an explicit act — it invalidates the
// diff, which is the truth, because a diff for a request you have changed is a
// lie about what you asked for.

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/texture.dart' show Hairline;
import '../../data/remote/api.dart';
import '../../domain/plan.dart';

class PlanRewriteSheet extends StatefulWidget {
  const PlanRewriteSheet({
    super.key,
    required this.plan,
    required this.locked,
    required this.run,
    required this.whoReads,
    required this.endpointLine,
  });

  final ReadingPlan plan;

  /// Shared with the frame, which reads it to decide whether Close closes.
  final ValueNotifier<bool> locked;

  /// Does the call. Throws [RemoteFailure] with a sentence to show.
  final Future<PlanRewrite> Function(String request) run;

  /// Two lines of the cost block, handed in rather than looked up, so the sheet
  /// states the same endpoint the Settings pane does.
  final String whoReads;
  final String endpointLine;

  /// Show it. Resolves to the accepted plan, or null if the reader kept theirs.
  static Future<ReadingPlan?> show(
    BuildContext context, {
    required ReadingPlan plan,
    required Future<PlanRewrite> Function(String request) run,
    required String whoReads,
    required String endpointLine,
  }) {
    final ValueNotifier<bool> locked = ValueNotifier<bool>(false);
    return AppSheet.showGated<ReadingPlan>(
      context,
      locked: locked,
      title: 'What should change?',
      // The frame's one Close, under the name that is true here. There is
      // deliberately no second button saying the same thing.
      closeLabel: 'Keep my plan',
      lockMessage: 'Use this plan, or edit your request',
      builder: (BuildContext ctx) => PlanRewriteSheet(
        plan: plan,
        locked: locked,
        run: run,
        whoReads: whoReads,
        endpointLine: endpointLine,
      ),
    );
  }

  @override
  State<PlanRewriteSheet> createState() => _PlanRewriteSheetState();
}

class _PlanRewriteSheetState extends State<PlanRewriteSheet> {
  /// Owned here, and disposed here.
  ///
  /// A controller created inside `build` leaks one per frame and loses the
  /// caret on every rebuild — the lesson recorded at the top of `sheets.dart`.
  final TextEditingController _request = TextEditingController();

  bool _busy = false;

  /// The unaccepted proposal, or null.
  PlanRewrite? _rewrite;

  /// The proposal as it stands NOW — the AI's answer with the reader's field
  /// corrections layered on. This, not the snapshot in `_rewrite.proposal`,
  /// is what `Use this plan` hands back.
  ReadingPlan? _edited;

  /// Which fields the reader has corrected since the AI answered, for the
  /// small `edited` mark on the row. Cleared with each new Run.
  final Set<PlanField> _touched = <PlanField>{};

  /// A sentence to show when the call failed. Cleared by the next Run.
  String? _error;

  /// The six examples. Tapping one APPENDS to what is already there rather than
  /// replacing it: they are meant to be combined ("shorter sentences" plus
  /// "stop explaining C basics"), and a picker that overwrites makes combining
  /// impossible.
  static const List<String> _examples = <String>[
    'Make the sentences much shorter and simpler',
    'Stop explaining C basics — I know pointers',
    "Any finance word must be explained like I'm new to it",
    'Add lo-fi and ambient music to the topics',
    'Never start with background — go straight to the point',
    'Longer articles, around 500 words',
  ];

  /// The same suggestion chips Settings offers in its plan-field editors.
  ///
  /// Duplicated rather than shared because the chip picker can ONLY offer its
  /// presets — no free text — so a list field edited here would be read-only
  /// without them, and this sheet stays one self-contained file.
  static const List<String> _stylePresets = <String>[
    'start with the thing itself',
    'short sentences',
    'say it once',
    'no headings',
    'concrete examples',
  ];

  static const List<String> _glossPresets = <String>[
    'finance words',
    'anything where a wrong guess would be embarrassing',
    'anything with more than one meaning in this article',
  ];

  static const List<String> _avoidPresets = <String>[
    'background before the point',
    'anything I already know',
    'rhetorical questions',
    'a summary at the end',
  ];

  @override
  void dispose() {
    _request.dispose();
    super.dispose();
  }

  /// Any edit to the request makes the diff describe something nobody asked
  /// for. `PlanRewrite.invalidate` is the domain's word for that, and it is
  /// also what unlocks the sheet — the reader is no longer holding a result
  /// they have not answered for.
  void _onEdited(String _) {
    if (_rewrite == null) return;
    _rewrite!.invalidate();
    setState(() {});
    widget.locked.value = false;
  }

  Future<void> _run() async {
    final String text = _request.text.trim();
    if (text.isEmpty) {
      Toast.show(context, 'say what should change first — nothing was sent');
      return;
    }
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _rewrite = null;
      // A fresh call is a fresh proposal: the reader's corrections belonged
      // to the answer that is being replaced, so they go with it.
      _edited = null;
      _touched.clear();
    });
    // Unlocked while running: there is no result to protect yet, and a sheet
    // that traps the reader during a fifteen-second call is worse than one that
    // lets them leave.
    widget.locked.value = false;

    try {
      final PlanRewrite r = await widget.run(text);
      if (!mounted) return;
      setState(() {
        _rewrite = r;
        _edited = r.proposal;
      });
      // Locked only when there is something to lose. A rewrite that changed
      // nothing locks nothing, because there is nothing to accept.
      widget.locked.value = r.changes.isNotEmpty;
    } on RemoteFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message + e.cost);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'nothing was changed · $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply() {
    final PlanRewrite? r = _rewrite;
    final ReadingPlan? edited = _edited;
    if (r == null || edited == null) return;
    // `apply()` throws on a stale diff. The UI already hides the button in that
    // state, so this is the last line of defence rather than the first — but it
    // is a line, and it is why the domain type refuses rather than warns.
    // The editor's corrections ride along: what the reader sees in the diff is
    // exactly what lands.
    if (r.isStale) {
      Toast.show(context, 'your request changed — run it again');
      return;
    }
    Navigator.of(context).pop(r.apply(edited: edited));
  }

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sheetPad, 0, Gap.sheetPad, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _request,
            onChanged: _onEdited,
            maxLines: 3,
            minLines: 2,
            enabled: !_busy,
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 15,
              height: 1.5,
              color: c.ink,
            ),
            decoration: InputDecoration(
              hintText: 'Say it in your own words. Short is fine.',
              hintStyle: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 15,
                color: c.ink3,
              ),
              filled: true,
              fillColor: c.paperSunk,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.hair),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.hair),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.verm),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),

          const SizedBox(height: 14),
          Text(
            'Tap to add. They stack, so you can combine two or three.',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 12.5,
              color: c.ink3,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              for (final String e in _examples)
                Pill(
                  e,
                  mono: false,
                  onTap: _busy
                      ? null
                      : () {
                          final String cur = _request.text.trim();
                          _request.text = cur.isEmpty ? e : '$cur\n$e';
                          _request.selection = TextSelection.collapsed(
                              offset: _request.text.length);
                          _onEdited(_request.text);
                        },
                ),
            ],
          ),

          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            _errorBlock(c, _error!),
          ],

          if (_rewrite != null) ...<Widget>[
            const SizedBox(height: 18),
            _diff(c, _rewrite!),
          ],

          const SizedBox(height: 18),
          Hairline(color: c.hair),
          const SizedBox(height: 12),
          _cost(c),

          const SizedBox(height: 14),
          if (_rewrite != null && _rewrite!.changes.isNotEmpty && !_busy) ...[
            Btn(label: 'Use this plan', primary: true, onPressed: _apply),
            const SizedBox(height: 8),
            Text(
              'Nothing has changed yet. Articles already written stay exactly '
              'as they are — this only affects what gets written next.',
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 12.5,
                height: 1.6,
                color: c.ink3,
              ),
            ),
          ] else
            Btn(
              label: _busy ? 'Asking…' : 'Ask the AI to change it',
              primary: true,
              busy: _busy,
              onPressed: _busy ? null : _run,
            ),
        ],
      ),
    );
  }

  /// The diff, field by field. The old value is struck through and the new one
  /// is JADE — the app's colour for a good outcome that cost nothing to look at.
  /// Every row is also the way in to correct that new value before accepting.
  Widget _diff(Palette c, PlanRewrite r) {
    if (r.changes.isEmpty) {
      return Text(
        'The plan came back the same. Nothing to accept, and nothing was '
        'changed.',
        style: TextStyle(
          fontFamily: TypeScale.serif,
          fontSize: 13.5,
          height: 1.6,
          color: c.ink2,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(r.isStale ? 'What it proposed' : 'What will change'),
        if (r.isStale)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'You have edited your request since. Start again from a clean '
              'sheet — this proposal describes what you asked for before.',
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 12.5,
                height: 1.6,
                color: c.vermInk,
              ),
            ),
          ),
        for (final PlanChange ch in r.changes) _changeRow(c, r, ch),
      ],
    );
  }

  /// One proposed change — and the reader's way in to correct it before
  /// accepting. The whole row is the button, the same bargain as the Settings
  /// plan pane: the right edge says what tapping does, `edit` until it has
  /// been used and `edited` afterwards.
  ///
  /// The row set is the AI's and never shrinks: a field corrected back to its
  /// old value still shows (the reader may change their mind again), because
  /// a row that vanishes is a field they can no longer reach.
  Widget _changeRow(Palette c, PlanRewrite r, PlanChange ch) {
    final PlanField? field = ch.field;
    // What will actually land for this field, read from the edited proposal
    // on every build — so a correction shows up here with nothing else to
    // update. `now` and `was` use the same shapes the model's diff used
    // (lists comma-joined, lengths bare), or the strike-through would be
    // comparing two renderings instead of two values.
    final ReadingPlan nowPlan = _edited ?? r.proposal;
    final String now = field == null ? ch.now : _valueOf(nowPlan, field);
    final bool touched = field != null && _touched.contains(field);
    // No way in while the diff is stale: the proposal describes a request
    // that no longer exists, and the way out is a fresh Run, not surgery.
    final bool canEdit = field != null && !r.isStale;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canEdit ? () => _editChange(ch) : null,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    ch.fieldLabel.toUpperCase(),
                    style: TextStyle(
                      fontFamily: TypeScale.mono,
                      fontSize: 10,
                      letterSpacing: 0.14,
                      color: c.ink3,
                    ),
                  ),
                  const Spacer(),
                  if (canEdit)
                    Text(
                      touched ? 'edited' : 'edit',
                      style: TextStyle(
                        fontFamily: TypeScale.sans,
                        fontSize: 11,
                        color: touched ? c.verm : c.ink3,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              if (ch.was.trim().isNotEmpty)
                Text(
                  ch.was,
                  style: TextStyle(
                    fontFamily: TypeScale.serif,
                    fontSize: 13.5,
                    height: 1.5,
                    color: c.ink3,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: c.ink3,
                  ),
                ),
              Text(
                now.trim().isEmpty ? '(cleared)' : now,
                style: TextStyle(
                  fontFamily: TypeScale.serif,
                  fontSize: 14.5,
                  height: 1.5,
                  color: c.jade,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Correct ONE proposed field, in place. The call is not repeated: the
  /// model's answer stays the base and this is the reader's edit on top of
  /// it, which is the whole point — they should not have to pay for a second
  /// call (or lose the first proposal to a stale request) to fix one word.
  Future<void> _editChange(PlanChange ch) async {
    final PlanField? field = ch.field;
    final ReadingPlan? base = _edited;
    final PlanRewrite? r = _rewrite;
    if (field == null || base == null || r == null || r.isStale) return;

    ReadingPlan next = base;

    switch (field) {
      case PlanField.reader:
        final String? v = await TextPromptSheet.ask(
          context,
          title: 'Reader',
          hint: 'software developer, comfortable with code, new to finance '
              'English',
          note: 'This is the vocabulary ceiling: it tells the writer how much '
              'it may assume.',
          // Unlike Settings (which sets an empty reader from scratch), the
          // proposal's own words are the starting point — opening this box
          // must not look like an offer to wipe what the AI wrote.
          initial: base.reader,
        );
        if (v == null) return;
        next = base.copyWith(reader: v);
        break;

      case PlanField.style:
        final List<String>? v = await ChipPickerSheet.ask(
          context,
          title: 'Style',
          note: 'How it should read.',
          initial: base.style,
          // The AI may propose words no preset lists. Merging the current
          // value into the chips means those show up ticked and can be
          // REMOVED — otherwise a custom proposal is permanent.
          presets: <String>{..._stylePresets, ...base.style}.toList(),
        );
        if (v == null) return;
        next = base.copyWith(style: v);
        break;

      case PlanField.gloss:
        final List<String>? v = await ChipPickerSheet.ask(
          context,
          title: 'Explain',
          note: 'Which words get the plain-language treatment.',
          initial: base.gloss,
          presets: <String>{..._glossPresets, ...base.gloss}.toList(),
        );
        if (v == null) return;
        next = base.copyWith(gloss: v);
        break;

      case PlanField.avoid:
        final List<String>? v = await ChipPickerSheet.ask(
          context,
          title: 'Avoid',
          note: 'The negative space. This is the one field that can stop a '
              'fluent-but-wrong draft.',
          initial: base.avoid,
          presets: <String>{..._avoidPresets, ...base.avoid}.toList(),
        );
        if (v == null) return;
        next = base.copyWith(avoid: v);
        break;

      // One editor for the three bands, as in Settings — three copies of the
      // same dialog is three chances for them to drift apart.
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
          value: base.wordsFor(band),
          min: 50,
          max: 2000,
          step: 25,
          suffix: 'words',
        );
        if (v == null) return;
        next = switch (band) {
          LengthBand.short => base.copyWith(shortWords: v),
          LengthBand.medium => base.copyWith(mediumWords: v),
          LengthBand.long => base.copyWith(longWords: v),
          LengthBand.custom => base,
        };
        break;
    }

    if (!mounted) return;
    // Saving the box back unchanged records nothing: an `edited` mark that
    // lies is worse than no mark at all.
    if (_valueOf(next, field) == _valueOf(base, field)) return;
    setState(() {
      _edited = next;
      _touched.add(field);
    });
  }

  /// One field as the diff shows it. Mirrors the shapes `_diff` in `writer.dart`
  /// produced for the model's answer, so a corrected value sits on the same
  /// line as the one it replaces without the rendering shifting.
  String _valueOf(ReadingPlan p, PlanField f) => switch (f) {
        PlanField.reader => p.reader,
        PlanField.style => p.style.join(', '),
        PlanField.gloss => p.gloss.join(', '),
        PlanField.avoid => p.avoid.join(', '),
        PlanField.lengthShort => '${p.shortWords}',
        PlanField.lengthMedium => '${p.mediumWords}',
        PlanField.lengthLong => '${p.longWords}',
      };

  /// Which band a length row edits. Total by construction: every member of
  /// `PlanField.lengths` maps to a band, and the throw is unreachable.
  static LengthBand _bandOf(PlanField f) => switch (f) {
        PlanField.lengthShort => LengthBand.short,
        PlanField.lengthMedium => LengthBand.medium,
        PlanField.lengthLong => LengthBand.long,
        _ => throw ArgumentError('$f is not a length field'),
      };

  Widget _errorBlock(Palette c, String message) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.vermWash,
        borderRadius: BorderRadius.circular(11),
      ),
      padding: const EdgeInsets.all(12),
      child: Text(
        message,
        style: TextStyle(
          fontFamily: TypeScale.serif,
          fontSize: 13,
          height: 1.6,
          color: c.vermInk,
        ),
      ),
    );
  }

  /// What the call will cost and where it goes, stated BEFORE the button. A
  /// price shown afterwards is not a price, it is a receipt.
  Widget _cost(Palette c) {
    Widget row(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 92,
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: TypeScale.mono,
                    fontSize: 10.5,
                    letterSpacing: 0.1,
                    color: c.ink3,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontFamily: TypeScale.mono,
                    fontSize: 11,
                    height: 1.45,
                    color: color ?? c.ink2,
                  ),
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        row('Who reads it', widget.whoReads),
        row('Endpoint', widget.endpointLine),
        row('Changes', 'your plan only — articles already written stay'),
        // Vermilion, because this one spends. The free rows in this app are
        // jade and this is deliberately not one of them.
        row('Cost', '~\$0.002 · one call · ~15 s', color: c.verm),
      ],
    );
  }
}
