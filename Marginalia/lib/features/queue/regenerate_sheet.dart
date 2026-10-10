// "Change it" — what a planned card's ⋯ menu opens.
//
// Two questions, and neither of them is a topic.
//
// **What should it be about?** Either a sentence the reader types, or a saved
// instruction they pick, or nothing at all — in which case the writer chooses,
// which is the ordinary case and is offered as a first-class answer rather than
// as an empty box.
//
// **How long?** Short, medium, long, a random draw, or an exact number.
//
// What used to be here was a topic chip and a "lens" chip. Both were labels the
// reader had to maintain in advance, and neither could express the thing people
// actually want to say — which is a sentence, not a noun. "Explain how a limit
// order fills, for someone who has never traded" was impossible to enter; it
// had to be approximated as `Finance` plus `how it works`, and the article came
// back generic because the request was generic.
//
// Everything here is FREE and the sheet says so in jade. Choosing what to write
// costs nothing; writing it is the tap that costs, and it happens on the card.

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/texture.dart' show Hairline;
import '../../domain/instruction.dart';
import '../../domain/plan.dart';

/// What the reader asked for. Returned by the sheet, applied by the queue.
///
/// [band] is [LengthBand.custom] exactly when [exactWords] is meaningful — the
/// two are one answer, and keeping them in one object is what stops a caller
/// from applying a number while labelling it `medium`.
class PlanRequest {
  const PlanRequest({
    required this.instruction,
    required this.band,
    required this.exactWords,
    this.instructionId,
    this.random = false,
  });

  /// The reader's own words. Empty means the writer picks the subject.
  final String instruction;

  /// Which saved instruction it came from, when it came from one. Null for
  /// something typed here and for a free pick.
  final String? instructionId;

  final LengthBand band;

  /// Only read when [band] is [LengthBand.custom].
  final int exactWords;

  /// "One of the three, you choose." A flag rather than a fifth [LengthBand],
  /// because it is not a length: it is an instruction, and the band it lands on
  /// is only known once the card is planned.
  final bool random;
}

/// How many saved instructions the picker shows before sending the reader to
/// the manager.
///
/// Ten is a screenful and a bit. The point is that the picker stays a picker:
/// a list long enough to need searching has stopped being something you can
/// glance at while deciding what to read.
const int kRecentInstructions = 10;

class RegenerateSheet extends StatefulWidget {
  const RegenerateSheet({
    super.key,
    required this.initialInstruction,
    required this.initialInstructionId,
    required this.initialBand,
    required this.initialWords,
    required this.plan,
    required this.instructions,
    required this.onSeeAll,
  });

  final String initialInstruction;
  final String? initialInstructionId;
  final LengthBand initialBand;
  final int initialWords;

  /// For the band labels: "Short · about 180 words".
  final ReadingPlan plan;

  /// The most recent few. The sheet never holds the whole collection — that is
  /// the manager's job, and a picker that has to page is not a picker.
  final List<Instruction> instructions;

  /// Opens Settings → Instructions. The sheet closes first; a reader who wants
  /// to edit their saved instructions is leaving this decision for later, and
  /// pretending otherwise would mean two sheets stacked on one another.
  final VoidCallback onSeeAll;

  @override
  State<RegenerateSheet> createState() => _RegenerateSheetState();
}

class _RegenerateSheetState extends State<RegenerateSheet> {
  late String _instruction = widget.initialInstruction;
  late String? _instructionId = widget.initialInstructionId;
  late LengthBand _band = widget.initialBand;
  late int _words = widget.initialWords > 0 ? widget.initialWords : 300;
  bool _random = false;

  /// True while the reader is typing something new, rather than picking.
  bool _typing = false;

  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Typing is the state you are in when the current instruction came from
    // nowhere saved — a hand-typed one, or nothing at all with no saved pick
    // made yet. Opening straight into the saved list when there IS one is the
    // common case: the reader is reusing something that worked.
    _typing = widget.initialInstruction.isNotEmpty &&
        widget.initialInstructionId == null;
    _text.text = widget.initialInstruction;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _pick(Instruction i) => setState(() {
        _instruction = i.text;
        _instructionId = i.id;
        _typing = false;
      });

  void _pickFree() => setState(() {
        _instruction = '';
        _instructionId = null;
        _typing = false;
      });

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
            'What should it be?',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.02,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nothing here is written or paid for. The card keeps its place in '
            'the queue either way.',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13,
              height: 1.6,
              color: c.ink3,
            ),
          ),

          const SizedBox(height: 18),
          const SectionLabel('What it is about'),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              // "You decide" is a CHOICE, not an empty state, and it is listed
              // first because it is what most articles are.
              Pill(
                'You decide',
                mono: false,
                color: _instruction.isEmpty ? c.ink : null,
                background: _instruction.isEmpty ? c.surface : null,
                borderColor: _instruction.isEmpty ? c.verm : null,
                onTap: _pickFree,
              ),
              for (final Instruction i in widget.instructions)
                Pill(
                  i.chipLabel(),
                  mono: false,
                  color: _instructionId == i.id ? c.ink : null,
                  background: _instructionId == i.id ? c.surface : null,
                  borderColor: _instructionId == i.id ? c.verm : null,
                  onTap: () => _pick(i),
                ),
              Pill(
                '✎ Write a new one',
                mono: false,
                color: _typing ? c.ink : null,
                background: _typing ? c.surface : null,
                borderColor: _typing ? c.verm : null,
                onTap: () => setState(() {
                  _typing = true;
                  _instructionId = null;
                }),
              ),
            ],
          ),

          if (_typing) ...<Widget>[
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              onChanged: (String v) => setState(() {
                _instruction = v;
                _instructionId = null;
              }),
              minLines: 2,
              maxLines: 4,
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 15,
                height: 1.5,
                color: c.ink,
              ),
              decoration: InputDecoration(
                hintText: 'Say what you want, in your own words. A sentence is '
                    'better than a word.',
                hintStyle: TextStyle(
                  fontFamily: TypeScale.serif,
                  fontSize: 14.5,
                  height: 1.5,
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
          ],

          if (widget.instructions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            // The manager, one tap away. Only offered when there is something
            // to manage — a link to an empty screen is a link that teaches the
            // reader the app has empty screens.
            InkWell(
              // Popped with NO result, which the caller reads as "cancel". That
              // is right: the reader did not answer the question this sheet
              // asked, they went to edit the answers available to it. Applying
              // the current selection on the way out would be applying a choice
              // they never confirmed.
              onTap: () {
                Navigator.of(context).pop();
                widget.onSeeAll();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'See all saved instructions ›',
                  style: TextStyle(
                    fontFamily: TypeScale.sans,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.verm,
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),
          const SectionLabel('Length'),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              for (final LengthBand b in <LengthBand>[
                LengthBand.short,
                LengthBand.medium,
                LengthBand.long,
              ])
                Pill(
                  '${b.label} · ~${widget.plan.wordsFor(b)}',
                  mono: false,
                  color: !_random && _band == b ? c.ink : null,
                  background: !_random && _band == b ? c.surface : null,
                  borderColor: !_random && _band == b ? c.verm : null,
                  onTap: () => setState(() {
                    _random = false;
                    _band = b;
                  }),
                ),
              Pill(
                'Random',
                mono: false,
                color: _random ? c.ink : null,
                background: _random ? c.surface : null,
                borderColor: _random ? c.verm : null,
                onTap: () => setState(() => _random = true),
              ),
              Pill(
                'An exact number',
                mono: false,
                color: !_random && _band == LengthBand.custom ? c.ink : null,
                background: !_random && _band == LengthBand.custom ? c.surface : null,
                borderColor: !_random && _band == LengthBand.custom ? c.verm : null,
                onTap: () => setState(() {
                  _random = false;
                  _band = LengthBand.custom;
                }),
              ),
            ],
          ),

          // The number row appears only when it is the answer. Showing a stepper
          // beside a band choice invites the reader to set two lengths and then
          // wonder which one won.
          if (!_random && _band == LengthBand.custom) ...<Widget>[
            const SizedBox(height: 12),
            _stepper(c),
          ],

          if (_random) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              'One of the three, drawn when the card is planned. Tap ↻ on the '
              'card for another draw.',
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 12.5,
                height: 1.55,
                color: c.ink3,
              ),
            ),
          ],

          const SizedBox(height: 18),
          Hairline(color: c.hair),
          const SizedBox(height: 12),
          _cost(c),

          const SizedBox(height: 14),
          Btn(
            label: 'Use this',
            primary: true,
            onPressed: () => Navigator.of(context).pop(
              PlanRequest(
                instruction: _instruction.trim(),
                instructionId: _instructionId,
                // A random draw still carries a band, so a caller that ignores
                // the flag gets a sensible plan rather than a crash.
                band: _random ? LengthBand.medium : _band,
                exactWords: _words,
                random: _random,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepper(Palette c) {
    return Row(
      children: <Widget>[
        _step(c, '−', () => setState(() => _words = (_words - 25).clamp(50, 2000))),
        Expanded(
          child: Text(
            '$_words words',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: TypeScale.mono,
              fontSize: 15,
              color: c.ink,
            ),
          ),
        ),
        _step(c, '+', () => setState(() => _words = (_words + 25).clamp(50, 2000))),
      ],
    );
  }

  Widget _step(Palette c, String label, VoidCallback onTap) {
    return Material(
      color: c.paperSunk,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 46,
          height: 40,
          child: Center(
            child: Text(label, style: TextStyle(fontSize: 19, color: c.ink)),
          ),
        ),
      ),
    );
  }

  /// The cost line. JADE, never vermilion: this sheet spends nothing, and
  /// vermilion is reserved for the thing that does.
  Widget _cost(Palette c) {
    return Row(
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: c.jade, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'free · nothing is written · nothing is paid for',
            style: TextStyle(
              fontFamily: TypeScale.mono,
              fontSize: 11,
              color: c.jade,
            ),
          ),
        ),
      ],
    );
  }
}
