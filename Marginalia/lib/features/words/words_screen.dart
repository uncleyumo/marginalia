// The word pool.
//
// This screen replaces spaced repetition entirely, and the copy says so. There
// is no due date, no interval, no "review these on Friday", and no percentage
// retention — because a weight bar labelled with a day would be a promise the
// app cannot keep: it never schedules anything, it only makes heavy words more
// likely to turn up in an article you read.
//
// What the bar IS, stated on the card itself: "how likely this word is picked".
// Not a schedule. Not a promise. A number, honestly labelled.
//
// "All words" is a REVIEW list, not a transcript of the article. Function
// words (`the`, `and`, `for`, `has`) are filtered out at the pool boundary —
// they were met, but reviewing them teaches nobody anything, and a list padded
// with them hides the words that need another showing.

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/back_label.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/texture.dart';

class WordRow {
  const WordRow({
    required this.lemma,
    required this.encounters,
    required this.starred,
    required this.starCount,
    required this.starRemaining,
    required this.fraction,
  });

  final String lemma;
  final int encounters;

  /// Whether a star campaign is still running.
  final bool starred;

  /// Lifetime star taps — what the reader has asked for this word, in total.
  final int starCount;

  /// Future articles that still owe the word a showing. Zero means the star
  /// has been fulfilled and the word is no longer in "Crucial now" because of
  /// it (it can still appear there on ordinary weight).
  final int starRemaining;

  /// 0–1, the share of the pool's total weight this word holds.
  final double fraction;
}

class WordsScreen extends StatefulWidget {
  const WordsScreen({
    super.key,
    required this.crucial,
    required this.all,
    required this.onStar,
    required this.onUnstar,
    required this.onOpen,
    this.onBack,
  });

  /// The front of the pool: the words most likely to come round again.
  final List<WordRow> crucial;

  /// Everything met that is worth reviewing. Function words have already been
  /// removed by [WordPool]; this list is the reader's real vocabulary.
  final List<WordRow> all;

  /// Tap = star again. Every tap adds a showing to the promise.
  final void Function(String lemma) onStar;

  /// Long-press = stop asking. Kept off the main tap because the request the
  /// prototype centres on is "I need this word more", not "I changed my mind".
  final void Function(String lemma) onUnstar;
  final void Function(String lemma) onOpen;

  /// The header label is a button. It was plain `Text`, so it named a
  /// destination and did nothing when touched — which is worse than having no
  /// label, because it teaches the reader to reach for the system Back instead.
  final VoidCallback? onBack;

  @override
  State<WordsScreen> createState() => _WordsScreenState();
}

class _WordsScreenState extends State<WordsScreen> {
  final TextEditingController _search = TextEditingController();

  /// Empty means "no filter". Lower-cased once, on change.
  String _query = '';

  /// The list is a record, but it can be hundreds of rows long. The first
  /// screenful is enough to browse; the rest is one tap away.
  bool _showAll = false;

  static const int _firstPage = 18;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<WordRow> get _matches {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.all;
    return widget.all
        .where((WordRow w) => w.lemma.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final List<WordRow> matches = _matches;
    final bool filtering = _query.trim().isNotEmpty;
    final bool collapsed =
        !filtering && !_showAll && matches.length > _firstPage;
    final List<WordRow> visible =
        collapsed ? matches.take(_firstPage).toList() : matches;

    return PageScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.gutter, 6, Gap.gutter, 30),
        children: <Widget>[
          Row(
            children: <Widget>[
              if (widget.onBack != null)
                BackLabel(label: '‹ Queue', onTap: widget.onBack!)
              else
                Text('‹ Queue',
                    style: TextStyle(
                      fontFamily: TypeScale.sans,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.ink2,
                    )),
              const Spacer(),
              Text(
                '${widget.all.length} words met',
                style: TextStyle(
                  fontFamily: TypeScale.mono,
                  fontSize: 10.5,
                  color: c.ink3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Eyebrow('Words · no schedule, no score'),
          Text('Your words', style: context.texts.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Words you looked up while reading. Everyday grammar words — the, '
            'and, for, has — are left out: they were met, but they are not '
            'worth reviewing. Nothing here has a due date, and nothing can be '
            'marked wrong.\n\n'
            'A star is a finite promise: tap ★ once and the next suitable '
            'article must use the word; tap it again and two must. The row '
            'says how many are still owed, and the word leaves Crucial now '
            'when the last one lands. Hold ★ to stop asking.',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13,
              height: 1.6,
              color: c.ink3,
            ),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Crucial now'),
          const SizedBox(height: 4),
          if (widget.crucial.isEmpty)
            Text(
              'Meet a few words in an article and they will gather here.',
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 13.5,
                height: 1.6,
                color: c.ink3,
              ),
            )
          else
            ...widget.crucial.map((WordRow w) => _barRow(context, c, w)),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              // SectionLabel ends in an Expanded hairline, so it needs a
              // BOUNDED width. As a bare child of a Row it got unbounded
              // constraints and threw during layout — which blanked the whole
              // list, not just this header.
              const Expanded(child: SectionLabel('All words')),
              if (filtering)
                Text(
                  '${matches.length} match${matches.length == 1 ? '' : 'es'}',
                  style: TextStyle(
                    fontFamily: TypeScale.mono,
                    fontSize: 10.5,
                    color: c.ink3,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _searchField(c),
          const SizedBox(height: 4),
          if (widget.all.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Nothing yet. Tap a word in an article and it will appear here.',
                style: TextStyle(
                  fontFamily: TypeScale.serif,
                  fontSize: 13.5,
                  height: 1.5,
                  color: c.ink3,
                ),
              ),
            )
          else if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No word here contains “${_query.trim()}”.',
                style: TextStyle(
                  fontFamily: TypeScale.serif,
                  fontSize: 13.5,
                  height: 1.5,
                  color: c.ink3,
                ),
              ),
            )
          else ...<Widget>[
            // English first in this list, because the reader is the one who has
            // to recognise it on the page. The Chinese sits behind a tap.
            ...visible.map((WordRow w) => _plainRow(context, c, w)),
            if (collapsed) ...<Widget>[
              const SizedBox(height: 10),
              Btn(
                label: 'Show all ${matches.length} words',
                primary: false,
                dense: true,
                onPressed: () => setState(() => _showAll = true),
              ),
            ] else if (!filtering && _showAll && matches.length > _firstPage)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Btn(
                  label: 'Show fewer',
                  primary: false,
                  dense: true,
                  onPressed: () => setState(() => _showAll = false),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _searchField(Palette c) {
    return Container(
      decoration: BoxDecoration(
        color: c.paperSunk,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.hair),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Row(
        children: <Widget>[
          Icon(Icons.search, size: 16, color: c.ink3),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(
                fontFamily: TypeScale.sans,
                fontSize: 14,
                color: c.ink,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Find a word',
                hintStyle: TextStyle(
                  fontFamily: TypeScale.sans,
                  fontSize: 13.5,
                  color: c.ink3,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (String v) => setState(() => _query = v),
            ),
          ),
          if (_query.isNotEmpty)
            InkWell(
              onTap: () {
                _search.clear();
                setState(() => _query = '');
              },
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close, size: 15, color: c.ink3),
              ),
            ),
        ],
      ),
    );
  }

  /// A word with its weight bar. The label under the bar is the honest one.
  Widget _barRow(BuildContext context, Palette c, WordRow w) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: InkWell(
        onTap: () => widget.onOpen(w.lemma),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // Expanded, not a bare Text plus a Spacer: a long lemma
                  // would otherwise push the counters off the row.
                  Expanded(
                    child: Text(
                      w.lemma,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: TypeScale.serif,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (w.starred) ...<Widget>[
                    Icon(Icons.star, size: 13, color: c.verm),
                    const SizedBox(width: 4),
                    Text(
                      'starred ${w.starCount}×',
                      style: TextStyle(
                        fontFamily: TypeScale.mono,
                        fontSize: 10,
                        color: c.verm,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    'met ${w.encounters}×',
                    style: TextStyle(
                      fontFamily: TypeScale.mono,
                      fontSize: 10.5,
                      color: c.ink3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              HatchedBar(
                fraction: w.fraction,
                color: w.starred ? c.verm : c.lamp,
                height: 6,
              ),
              const SizedBox(height: 5),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      // A star is a promise with a number on it; everything
                      // else here is a probability. Saying which is which is
                      // what stops "weighted" reading as "scheduled".
                      w.starred
                          ? '${w.starRemaining == 1 ? '1 more article' : '${w.starRemaining} more articles'} must use it · tap ★ to ask again'
                          : 'how likely this word is picked · not a promise of which day',
                      style: TextStyle(
                        fontFamily: TypeScale.sans,
                        fontSize: 10.5,
                        color: w.starred ? c.verm : c.ink3,
                      ),
                    ),
                  ),
                  _Star(
                    lemma: w.lemma,
                    starred: w.starred,
                    onStar: widget.onStar,
                    onUnstar: widget.onUnstar,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _plainRow(BuildContext context, Palette c, WordRow w) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onOpen(w.lemma),
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    w.lemma,
                    style: TextStyle(
                      fontFamily: TypeScale.serif,
                      fontSize: 15.5,
                      color: c.ink,
                    ),
                  ),
                ),
                if (w.starCount > 0) ...<Widget>[
                  Text(
                    '★${w.starCount}',
                    style: TextStyle(
                      fontFamily: TypeScale.mono,
                      fontSize: 10.5,
                      color: w.starred ? c.verm : c.ink3,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  '${w.encounters}×',
                  style: TextStyle(
                    fontFamily: TypeScale.mono,
                    fontSize: 10.5,
                    color: c.ink3,
                  ),
                ),
                const SizedBox(width: 8),
                _Star(
                  lemma: w.lemma,
                  starred: w.starred,
                  onStar: widget.onStar,
                  onUnstar: widget.onUnstar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A star. Starring raises the weight IMMEDIATELY and never rewrites an article
/// that already exists — it must not, because that would spend money nobody
/// agreed to spend.
class _Star extends StatelessWidget {
  const _Star({
    required this.lemma,
    required this.starred,
    required this.onStar,
    required this.onUnstar,
  });

  final String lemma;
  final bool starred;
  final void Function(String lemma) onStar;
  final void Function(String lemma) onUnstar;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Tooltip(
      message: starred
          ? 'tap to star again · hold to stop asking'
          : 'ask for this one again · free, and rewrites nothing',
      child: SizedBox(
        width: 32,
        height: 28,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => onStar(lemma),
            // Long-press, not a second tap: the second tap belongs to "I need
            // this word even more", which is the prototype's rule.
            onLongPress: starred ? () => onUnstar(lemma) : null,
            customBorder: const CircleBorder(),
            child: Center(
              child: Icon(
                starred ? Icons.star : Icons.star_border,
                size: 16,
                color: starred ? c.verm : c.ink3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
