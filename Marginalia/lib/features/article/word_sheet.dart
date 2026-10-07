// The word sheet.
//
// The interaction that makes this app what it is: you tapped a word, and the
// ENGLISH appears. Not a dictionary entry, not IPA-first, not a modal that opens
// already scrolled past the answer. The English line, large, on top.
//
// Chinese is one tap further. That order is not a preference — DESIGN's reason
// is the right one: "you asked in English, you get English first; the Chinese is
// the extra tap, and the extra tap is what makes it feel like an answer rather
// than a lookup table."
//
// Everything on this sheet is in English. The ONLY Chinese on screen is the
// translation itself. A label that says what a button does in the reader's own
// language is not a courtesy, it is the interface: `tap for 中文` told a reader
// nothing except that the app expected them to read two scripts to find out how
// to dismiss a row.
//
// A miss is stated plainly. There is no API fallback: DESIGN's promise is that a
// lookup costs nothing, works offline and works in airplane mode, so a word that
// is not in the shipped dictionary is a fact to say out loud, not a gap to paper
// over with a network call.

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/texture.dart' show HatchedBar;
import '../../data/dictionary.dart';

/// The word sheet. Shows the surface as tapped, and the lemma it resolved to
/// when they differ — which is how `crashes` quietly explains `crash`.
///
/// STATE LIVES HERE, not in the parent. The sheet was previously handed a
/// `starred` flag it could not change, so tapping "want this again" fired a
/// toast, re-rendered the sheet with the same value it already had, and left the
/// reader tapping a button that never appeared to do anything. A control whose
/// state cannot change is worse than no control, because it teaches the reader
/// that this app does not respond.
class WordSheet extends StatefulWidget {
  const WordSheet({
    super.key,
    required this.surface,
    required this.entry,
    required this.miss,
    required this.starred,
    required this.onToggleStar,
    required this.onSpeak,
    this.lemma,
    this.weightFraction,
  });

  final String surface;
  final DictEntry entry;
  final LookupMiss miss;

  /// The state as it was when the sheet opened. The sheet then owns it.
  final bool starred;
  final void Function(bool next) onToggleStar;
  final VoidCallback onSpeak;

  /// The dictionary form, when the tapped word was an inflection.
  final String? lemma;

  /// How likely this word is to be picked again. NOT a promise about which day.
  final double? weightFraction;

  @override
  State<WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends State<WordSheet> {
  late bool _starred = widget.starred;
  bool _showChinese = false;

  void _star() {
    // Flip locally first. The parent's write goes to the database and comes back
    // through a rebuild it may not have time to do; the reader has already
    // tapped, so the sheet must answer on this frame.
    setState(() => _starred = !_starred);
    widget.onToggleStar(_starred);
  }

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final bool found = widget.entry.hasEnglish || widget.entry.hasChinese;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sheetPad, 0, Gap.sheetPad, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _lemma(c),
          const SizedBox(height: 11),
          if (!found)
            _missNotice(c)
          else ...<Widget>[
            if (widget.entry.ipa.isNotEmpty) _ipa(c),
            if (widget.entry.en.isNotEmpty) _english(c),
            // A word with no English in the source data must SAY so rather than
            // show an empty gap the reader would read as a bug.
            if (widget.entry.en.isEmpty && widget.entry.hasChinese)
              _noEnglish(c),
            if (widget.entry.hasChinese) _translation(c),
          ],
          const SizedBox(height: 15),
          _actions(c, found),
        ],
      ),
    );
  }

  /// The lemma: 33px serif, the largest type in the app besides the hero. The
  /// word IS the content of this screen.
  Widget _lemma(Palette c) {
    final String? lemma = widget.lemma;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(lemma ?? widget.surface, style: MarginaliaTheme.lemma(c)),
        if (lemma != null) ...<Widget>[
          const SizedBox(height: 3),
          Text(
            'you tapped ${widget.surface}',
            style: TextStyle(
              fontFamily: TypeScale.mono,
              fontSize: 10.5,
              color: c.ink3,
            ),
          ),
        ],
      ],
    );
  }

  Widget _ipa(Palette c) {
    final String pos = widget.entry.pos;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              widget.entry.ipa,
              style: TextStyle(
                fontFamily: TypeScale.mono,
                fontSize: 13,
                color: c.ink2,
              ),
            ),
          ),
          if (pos.isNotEmpty) ...<Widget>[
            const SizedBox(width: 8),
            Text(
              pos,
              style: TextStyle(
                fontFamily: TypeScale.mono,
                fontSize: 10.5,
                color: c.ink3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The English gloss, on top, in serif, at reading size.
  Widget _english(Palette c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Text(
        widget.entry.en,
        style: TextStyle(
          fontFamily: TypeScale.serif,
          fontSize: 16,
          height: 1.65,
          color: c.ink,
        ),
      ),
    );
  }

  Widget _noEnglish(Palette c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Text(
        'No English gloss in the offline dictionary. The Chinese translation is '
        'below.',
        style: TextStyle(
          fontFamily: TypeScale.serif,
          fontSize: 13.5,
          fontStyle: FontStyle.italic,
          color: c.ink3,
        ),
      ),
    );
  }

  /// The translation, behind one tap.
  ///
  /// The control is a single quiet line that says which way it goes: `Chinese
  /// translation` with a chevron, then `Chinese translation` with an up-chevron
  /// once it is open. The old version repeated the word "Chinese" on both sides
  /// of the control, which made the label itself look like the thing being
  /// toggled.
  Widget _translation(Palette c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Material(
          color: _showChinese ? c.vermWash : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => setState(() => _showChinese = !_showChinese),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _showChinese ? c.verm : c.hair),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: <Widget>[
                  Icon(
                    _showChinese
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 17,
                    color: _showChinese ? c.vermInk : c.ink3,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Chinese translation',
                    style: TextStyle(
                      fontFamily: TypeScale.sans,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _showChinese ? c.vermInk : c.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_showChinese)
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 2),
            child: Text(
              widget.entry.cn,
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 15,
                height: 1.7,
                color: c.ink,
              ),
            ),
          ),
      ],
    );
  }

  /// The miss notice. Honest, brief, and it names the reason it can happen.
  Widget _missNotice(Palette c) {
    final bool loading = widget.miss == LookupMiss.notLoaded;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: c.paperSunk,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: c.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            loading
                ? 'The dictionary is still loading.'
                : 'Not in the offline dictionary.',
            style: TextStyle(
              fontFamily: TypeScale.sans,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            loading
                ? 'It inflates once on the first run — 392,695 words, about a '
                    'second. Try again in a moment.'
                : 'This app never looks a word up over the network, so it '
                    'cannot answer for words the dictionary does not carry. '
                    'Proper nouns, stock tickers and technical identifiers are '
                    'the usual ones.',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13.5,
              height: 1.6,
              color: c.ink2,
            ),
          ),
        ],
      ),
    );
  }

  /// Two compact actions in ONE row, side by side, the same height, neither
  /// stretched to half the sheet.
  ///
  /// The previous version used two full-width buttons stacked with 14px
  /// vertical padding, which on a 320dp-wide sheet produced a pair of very large
  /// blocks with a two-line label in one of them — the "big buttons and lopsided
  /// blocks" a screenshot showed. Equal width, equal height, one line each.
  Widget _actions(Palette c, bool found) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _ActionBtn(
                icon: Icons.volume_up_outlined,
                label: 'Say it',
                active: false,
                onTap: widget.onSpeak,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionBtn(
                icon: _starred ? Icons.star : Icons.star_border,
                label: _starred ? 'Starred' : 'Star it',
                // Vermilion when starred. The star FILLING is the primary
                // feedback; the colour change is what makes it findable again
                // when the eye goes back to the sheet.
                active: _starred,
                onTap: _star,
              ),
            ),
          ],
        ),
        if (_starred) ...<Widget>[
          const SizedBox(height: 9),
          Text(
            'It comes round again sooner. Nothing already written is changed.',
            style: TextStyle(
              fontFamily: TypeScale.sans,
              fontSize: 11.5,
              height: 1.4,
              color: c.ink3,
            ),
          ),
        ],
        if (widget.weightFraction != null) ...<Widget>[
          const SizedBox(height: 14),
          _weight(c, widget.weightFraction!),
        ],
        if (found && widget.entry.ipa.isEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            'This dictionary entry carries no pronunciation.',
            style: TextStyle(
              fontFamily: TypeScale.sans,
              fontSize: 11,
              color: c.ink3,
            ),
          ),
        ],
      ],
    );
  }

  /// The weight bar. DESIGN is explicit that this is "how likely the word is
  /// picked — not a promise of which day", so it is labelled that way and never
  /// rendered as a date or a streak.
  Widget _weight(Palette c, double fraction) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HatchedBar(fraction: fraction, color: c.lamp, height: 5),
        const SizedBox(height: 5),
        Text(
          'how likely this word is to come round again · not a promise of which '
          'day',
          style: TextStyle(
            fontFamily: TypeScale.sans,
            fontSize: 11,
            color: c.ink3,
          ),
        ),
      ],
    );
  }
}

/// One action in the sheet. Square-ish, compact, and never wider than half the
/// row it shares with an identical sibling.
class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Material(
      color: active ? c.vermWash : c.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? c.verm : c.hair),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 16, color: active ? c.vermInk : c.ink2),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: TypeScale.sans,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: active ? c.vermInk : c.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Open the sheet. Returns nothing; the caller owns the state it changes.
Future<void> showWordSheet(
  BuildContext context, {
  required String surface,
  required DictEntry entry,
  required LookupMiss miss,
  required bool starred,
  required void Function(bool next) onToggleStar,
  required VoidCallback onSpeak,
  String? lemma,
  double? weightFraction,
}) {
  return AppSheet.show<void>(
    context,
    builder: (BuildContext _) => WordSheet(
      surface: surface,
      entry: entry,
      miss: miss,
      starred: starred,
      onToggleStar: onToggleStar,
      onSpeak: onSpeak,
      lemma: lemma,
      weightFraction: weightFraction,
    ),
  );
}