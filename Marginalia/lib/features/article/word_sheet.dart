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

import 'package:flutter/gestures.dart';
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
    required this.starrable,
    required this.starCount,
    required this.starRemaining,
    required this.onStar,
    required this.onUnstar,
    required this.onSpeak,
    this.lemma,
    this.weightFraction,
    this.dictionary,
  });

  final String surface;
  final DictEntry entry;
  final LookupMiss miss;

  /// Whether this word is kept in the reader's pool at all. Function words
  /// (`the`, `and`) are answered and not recorded, so a star button on one
  /// would be a control that does nothing — worse than no control.
  final bool starrable;

  /// The star state as it was when the sheet opened. The sheet then owns the
  /// local copy so a tap answers on this frame.
  ///
  /// [starCount] is LIFETIME taps; [starRemaining] is how many future articles
  /// still owe this word. A word can be re-starred while it is already starred:
  /// every tap is a stronger request, not a toggle.
  final int starCount;
  final int starRemaining;
  final VoidCallback onStar;
  final VoidCallback onUnstar;
  final VoidCallback onSpeak;

  /// The dictionary form, when the tapped word was an inflection.
  final String? lemma;

  /// How likely this word is to be picked again. NOT a promise about which day.
  final double? weightFraction;

  /// The offline dictionary, when it has loaded. Words inside the English gloss
  /// look themselves up in it — the same one the main lookup uses, so a gloss
  /// word answers the same way a tapped word does, and equally offline. Null
  /// while the first inflate is still running.
  final Dictionary? dictionary;

  @override
  State<WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends State<WordSheet> {
  late int _starCount = widget.starCount;
  late int _starRemaining = widget.starRemaining;
  bool get _starred => _starRemaining > 0;
  bool _showChinese = false;

  /// The gloss word whose Chinese panel is open. `cn` and `note` are mutually
  /// exclusive: one carries the translation, the other says why there is none.
  /// A panel with neither would read as the app being broken.
  ({String word, String? cn, String? note})? _gloss;

  /// Every tap ADDS a showing. Tapping a starred word used to turn the star
  /// off, which made "I really mean it" impossible — and it meant a reader who
  /// tapped twice lost the request instead of doubling it.
  void _star() {
    setState(() {
      if (_starRemaining > 0) {
        _starCount++;
        _starRemaining++;
      } else {
        // A new campaign: the lifetime count rises, and that is the quota.
        _starCount++;
        _starRemaining = _starCount;
      }
    });
    widget.onStar();
  }

  void _unstar() {
    setState(() {
      _starCount = 0;
      _starRemaining = 0;
    });
    widget.onUnstar();
  }

  /// Look up a word tapped inside the English gloss. ONE step only — the panel
  /// this opens is plain text, because a translation of a translation is where
  /// a lookup stops being an answer and starts being a maze.
  void _tapGloss(String word) {
    final String key = word.toLowerCase();
    // Tapping the open word again closes it. The panel has its own close
    // control, but a tap that can only ever open teaches the reader to stop
    // tapping.
    if (_gloss?.word.toLowerCase() == key) {
      setState(() => _gloss = null);
      return;
    }
    final Dictionary? dict = widget.dictionary;
    if (dict == null) {
      setState(() => _gloss = (
            word: word,
            cn: null,
            note: 'The dictionary is still loading.',
          ));
      return;
    }
    final (DictEntry? entry, _) = dict.lookup(word);
    setState(() {
      if (entry == null || !entry.hasChinese) {
        _gloss = (
          word: word,
          cn: null,
          note: entry == null
              ? 'Not in the offline dictionary.'
              : 'This entry carries no Chinese.',
        );
      } else {
        _gloss = (word: word, cn: entry.cn, note: null);
      }
    });
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

  /// Words inside the gloss. Same shape the article's sentences use: a run of
  /// letters is tappable, the spaces and punctuation between them are not.
  static final RegExp _glossWord = RegExp(r"[A-Za-z][A-Za-z'\-]*");

  /// The English gloss, on top, in serif, at reading size — with every word in
  /// it a doorway to the same offline dictionary the main lookup uses.
  Widget _english(Palette c) {
    final String gloss = widget.entry.en;
    final TextStyle style = TextStyle(
      fontFamily: TypeScale.serif,
      fontSize: 16,
      height: 1.65,
      color: c.ink,
    );

    final List<TextSpan> children = <TextSpan>[];
    int cursor = 0;
    for (final RegExpMatch m in _glossWord.allMatches(gloss)) {
      if (m.start > cursor) {
        children.add(TextSpan(text: gloss.substring(cursor, m.start)));
      }
      final String word = m.group(0)!;
      // The word whose panel is open is inked vermilion — the same "this is the
      // one you asked about" the rest of the app uses for an active thing, and
      // the only feedback a span can give without a box drawn around it.
      final bool open = _gloss?.word.toLowerCase() == word.toLowerCase();
      children.add(TextSpan(
        text: word,
        style: open ? style.copyWith(color: c.vermInk) : null,
        recognizer: TapGestureRecognizer()..onTap = () => _tapGloss(word),
      ));
      cursor = m.end;
    }
    if (cursor < gloss.length) {
      children.add(TextSpan(text: gloss.substring(cursor)));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text.rich(TextSpan(style: style, children: children)),
          if (_gloss != null) _glossPanel(c),
        ],
      ),
    );
  }

  /// The Chinese-only panel under a tapped gloss word. Deliberately minimal —
  /// the word, the meaning, a way out — and NOT tappable itself: translation
  /// depth is capped at two, and this panel is the second step.
  Widget _glossPanel(Palette c) {
    final ({String word, String? cn, String? note}) g = _gloss!;
    return Container(
      margin: const EdgeInsets.only(top: 9),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 6),
      decoration: BoxDecoration(
        color: c.paperSunk,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: c.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  g.word,
                  style: TextStyle(
                    fontFamily: TypeScale.sans,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
              // An X rather than a word: the sheet's chrome is English-only,
              // and a symbol is a close button in every script at once.
              InkWell(
                onTap: () => setState(() => _gloss = null),
                borderRadius: BorderRadius.circular(7),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 15, color: c.ink3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (g.cn != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                g.cn!,
                style: TextStyle(
                  fontFamily: TypeScale.serif,
                  fontSize: 14.5,
                  height: 1.7,
                  color: c.ink,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                g.note ?? '',
                style: TextStyle(
                  fontFamily: TypeScale.sans,
                  fontSize: 12,
                  height: 1.4,
                  color: c.ink3,
                ),
              ),
            ),
        ],
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
            // Function words are not kept in the pool, so there is nothing
            // for a star to ask for. Hiding the button is the honest state:
            // a disabled control would still imply a word list it is not in.
            if (widget.starrable) ...<Widget>[
              const SizedBox(width: 8),
              Expanded(
                child: _ActionBtn(
                  icon: _starred ? Icons.star : Icons.star_border,
                  // While a campaign is running the button ADDS a showing. The
                  // count is on the button because "starred" alone hides the
                  // fact that the reader asked for it three times.
                  label: _starCount > 0 ? 'Star again · $_starCount' : 'Star it',
                  // Vermilion when starred. The star FILLING is the primary
                  // feedback; the colour change is what makes it findable again
                  // when the eye goes back to the sheet.
                  active: _starred,
                  onTap: _star,
                ),
              ),
            ],
          ],
        ),
        if (!_starred && _starCount > 0) ...<Widget>[
          const SizedBox(height: 9),
          Text(
            'The showing${_starCount == 1 ? '' : 's'} you asked for '
            '${_starCount == 1 ? 'has' : 'have'} been delivered. Starring again '
            'will ask for ${_starCount + 1}.',
            style: TextStyle(
              fontFamily: TypeScale.sans,
              fontSize: 11.5,
              height: 1.4,
              color: c.ink3,
            ),
          ),
        ],
        if (_starred) ...<Widget>[
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  _starRemaining == 1
                      ? 'One more article will use it, then it leaves Crucial now.'
                      : '$_starRemaining more articles will use it, then it leaves Crucial now.',
                  style: TextStyle(
                    fontFamily: TypeScale.sans,
                    fontSize: 11.5,
                    height: 1.4,
                    color: c.ink3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _unstar,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  child: Text(
                    'Stop',
                    style: TextStyle(
                      fontFamily: TypeScale.sans,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: c.verm,
                    ),
                  ),
                ),
              ),
            ],
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
  required bool starrable,
  required int starCount,
  required int starRemaining,
  required VoidCallback onStar,
  required VoidCallback onUnstar,
  required VoidCallback onSpeak,
  String? lemma,
  double? weightFraction,
  Dictionary? dictionary,
}) {
  return AppSheet.show<void>(
    context,
    builder: (BuildContext _) => WordSheet(
      surface: surface,
      entry: entry,
      miss: miss,
      starrable: starrable,
      starCount: starCount,
      starRemaining: starRemaining,
      onStar: onStar,
      onUnstar: onUnstar,
      onSpeak: onSpeak,
      lemma: lemma,
      weightFraction: weightFraction,
      dictionary: dictionary,
    ),
  );
}