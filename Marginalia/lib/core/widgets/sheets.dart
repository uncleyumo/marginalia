// The sheet bodies that ask the reader for something.
//
// Each of these used to be built inline in the Settings screen, opening
// `showModalBottomSheet` with a `TextEditingController` created OUTSIDE the
// sheet and disposed the instant `await` returned. That crashed on every text
// field in the app:
//
//     A TextEditingController was used after being disposed.
//
// The route is still animating out when `await` returns, so it rebuilds once
// more against a controller that has already been freed — and the follow-up
// failure is the red screen, because a widget that throws during a route
// transition takes the inherited theme down with it.
//
// So every sheet below is a StatefulWidget that OWNS its controller and frees
// it in its own `dispose()`, which is the only point at which that is legal.
//
// They are widgets rather than inline builders for a second reason as well: a
// sheet body that draws its own frame produces a SECOND Close button. Content
// goes in; `AppSheet.show` applies the frame exactly once.

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'primitives.dart';

/// One line of text. A sentence about the reader's work, a key, or a topic.
///
/// Returns the trimmed text, or null if the reader backed out.
class TextPromptSheet extends StatefulWidget {
  const TextPromptSheet({
    super.key,
    required this.hint,
    required this.note,
    this.initial = '',
    this.obscure = false,
    this.saveLabel = 'Save',
    this.mono = false,
  });

  final String hint;
  final String note;
  final String initial;
  final bool obscure;
  final String saveLabel;

  /// Mono for keys and identifiers, serif for sentences. A key is data;
  /// mono prose is hard to read.
  final bool mono;

  static Future<String?> ask(
    BuildContext context, {
    required String title,
    required String hint,
    required String note,
    String initial = '',
    bool obscure = false,
    String saveLabel = 'Save',
    bool mono = false,
  }) {
    return AppSheet.show<String>(
      context,
      title: title,
      builder: (BuildContext _) => TextPromptSheet(
        hint: hint,
        note: note,
        initial: initial,
        obscure: obscure,
        saveLabel: saveLabel,
        mono: mono,
      ),
    );
  }

  @override
  State<TextPromptSheet> createState() => _TextPromptSheetState();
}

class _TextPromptSheetState extends State<TextPromptSheet> {
  final TextEditingController _c = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c.text = widget.initial;
  }

  @override
  void dispose() {
    // The only correct place to free a controller. See the file header.
    _c.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).maybePop(_c.text.trim());

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final bool mono = widget.mono;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sheetPad, 2, Gap.sheetPad, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _c,
            autofocus: true,
            obscureText: widget.obscure,
            style: TextStyle(
              fontFamily: mono ? TypeScale.mono : TypeScale.serif,
              fontSize: mono ? 13 : 15.5,
              height: 1.5,
              color: c.ink,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(
                fontFamily: mono ? TypeScale.mono : TypeScale.serif,
                fontSize: mono ? 12 : 14,
                color: c.ink3,
              ),
              filled: true,
              fillColor: c.paperSunk,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.input),
                borderSide: BorderSide(color: c.hair),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.input),
                borderSide: BorderSide(color: c.hair),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.input),
                borderSide: BorderSide(color: c.verm, width: 1.4),
              ),
            ),
            onSubmitted: (String _) => _save(),
          ),
          const SizedBox(height: 13),
          Text(
            widget.note,
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13,
              height: 1.6,
              color: c.ink2,
            ),
          ),
          const SizedBox(height: 15),
          Btn(label: widget.saveLabel, onPressed: _save),
        ],
      ),
    );
  }
}

/// A number, stepped rather than typed: a number typed into a keyboard invites a
/// typo, and a typo here is an article that is 3 words long.
class NumberStepSheet extends StatefulWidget {
  const NumberStepSheet({
    super.key,
    required this.note,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    this.suffix = '',
  });

  final String note;
  final int value;
  final int min;
  final int max;
  final int step;

  /// Shown beside the number: `words`, `marked`. A bare integer on a screen is
  /// a number the reader has to interpret.
  final String suffix;

  static Future<int?> ask(
    BuildContext context, {
    required String title,
    required String note,
    required int value,
    required int min,
    required int max,
    required int step,
    String suffix = '',
  }) {
    return AppSheet.show<int>(
      context,
      title: title,
      builder: (BuildContext _) => NumberStepSheet(
        note: note,
        value: value,
        min: min,
        max: max,
        step: step,
        suffix: suffix,
      ),
    );
  }

  @override
  State<NumberStepSheet> createState() => _NumberStepSheetState();
}

class _NumberStepSheetState extends State<NumberStepSheet> {
  late int _value = widget.value.clamp(widget.min, widget.max);

  void _bump(int by) => setState(() {
        _value = (_value + by).clamp(widget.min, widget.max);
      });

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sheetPad, 2, Gap.sheetPad, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            widget.note,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13.5,
              height: 1.6,
              color: c.ink2,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _StepButton(
                icon: Icons.remove,
                onTap: () => _bump(-widget.step),
              ),
              SizedBox(
                width: 132,
                child: Column(
                  children: <Widget>[
                    Text(
                      '$_value',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: TypeScale.mono,
                        fontSize: 30,
                        height: 1.1,
                        color: c.ink,
                      ),
                    ),
                    if (widget.suffix.isNotEmpty)
                      Text(
                        widget.suffix,
                        style: TextStyle(
                          fontFamily: TypeScale.sans,
                          fontSize: 11,
                          color: c.ink3,
                        ),
                      ),
                  ],
                ),
              ),
              _StepButton(icon: Icons.add, onTap: () => _bump(widget.step)),
            ],
          ),
          const SizedBox(height: 22),
          Btn(
            label: 'Save',
            onPressed: () => Navigator.of(context).maybePop(_value),
          ),
        ],
      ),
    );
  }
}

/// One step of a number. Square, quiet, and hard to hit by accident.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return SizedBox(
      width: 46,
      height: 46,
      child: Material(
        color: c.paperSunk,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.hair),
            ),
            child: Icon(icon, size: 19, color: c.ink),
          ),
        ),
      ),
    );
  }
}

/// A chip picker, because the presets are a starting point and not a menu.
class ChipPickerSheet extends StatefulWidget {
  const ChipPickerSheet({
    super.key,
    required this.note,
    required this.initial,
    required this.presets,
  });

  final String note;
  final List<String> initial;
  final List<String> presets;

  /// Returns the picked list, or null if the reader backed out.
  static Future<List<String>?> ask(
    BuildContext context, {
    required String title,
    required String note,
    required List<String> initial,
    required List<String> presets,
  }) {
    return AppSheet.show<List<String>>(
      context,
      title: title,
      builder: (BuildContext _) => ChipPickerSheet(
        note: note,
        initial: initial,
        presets: presets,
      ),
    );
  }

  @override
  State<ChipPickerSheet> createState() => _ChipPickerSheetState();
}

class _ChipPickerSheetState extends State<ChipPickerSheet> {
  late List<String> _picked = List<String>.of(widget.initial);

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sheetPad, 2, Gap.sheetPad, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.note,
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13.5,
              height: 1.6,
              color: c.ink2,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              for (final String t in widget.presets)
                Pill(
                  t,
                  mono: false,
                  color: _picked.contains(t) ? c.paper : c.ink3,
                  background: _picked.contains(t) ? c.verm : null,
                  borderColor: _picked.contains(t) ? c.verm : null,
                  onTap: () => setState(() {
                    _picked.contains(t)
                        ? _picked.remove(t)
                        : _picked.add(t);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            _picked.isEmpty
                ? 'nothing set — the app decides for itself'
                : _picked.join(' · '),
            style: TextStyle(
              fontFamily: TypeScale.mono,
              fontSize: 10.5,
              height: 1.5,
              color: c.ink3,
            ),
          ),
          const SizedBox(height: 15),
          Btn(
            label: 'Save',
            onPressed: () => Navigator.of(context).maybePop(
                  List<String>.of(_picked),
                ),
          ),
        ],
      ),
    );
  }
}