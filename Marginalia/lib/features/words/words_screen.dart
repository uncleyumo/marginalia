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
    required this.fraction,
  });

  final String lemma;
  final int encounters;
  final bool starred;

  /// 0–1, the share of the pool's total weight this word holds.
  final double fraction;
}

class WordsScreen extends StatelessWidget {
  const WordsScreen({
    super.key,
    required this.crucial,
    required this.all,
    required this.onStar,
    required this.onOpen,
    this.onBack,
  });

  /// The front of the pool: the words most likely to come round again.
  final List<WordRow> crucial;

  /// Everything met. Not filtered by weight — the reader met all of them.
  final List<WordRow> all;

  final void Function(String lemma, bool starred) onStar;
  final void Function(String lemma) onOpen;

  /// The header label is a button. It was plain `Text`, so it named a
  /// destination and did nothing when touched — which is worse than having no
  /// label, because it teaches the reader to reach for the system Back instead.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return PageScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.gutter, 6, Gap.gutter, 30),
        children: <Widget>[
          Row(
            children: <Widget>[
              if (onBack != null)
                BackLabel(label: '‹ Queue', onTap: onBack!)
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
                '${all.length} words met',
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
            'A word you meet comes back on its own. Nothing here has a due '
            'date, and nothing can be marked wrong.',
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
          if (crucial.isEmpty)
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
            ...crucial.map((WordRow w) => _barRow(context, c, w)),
          const SizedBox(height: 10),
          const SectionLabel('All words'),
          const SizedBox(height: 4),
          if (all.isEmpty)
            Text(
              'Nothing yet.',
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 13.5,
                color: c.ink3,
              ),
            )
          else
            // English first in this list, because the reader is the one who has
            // to recognise it on the page. The Chinese sits behind a tap.
            ...all.map((WordRow w) => _plainRow(context, c, w)),
        ],
      ),
    );
  }

  /// A word with its weight bar. The label under the bar is the honest one.
  Widget _barRow(BuildContext context, Palette c, WordRow w) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: InkWell(
        onTap: () => onOpen(w.lemma),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    w.lemma,
                    style: TextStyle(
                      fontFamily: TypeScale.serif,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (w.starred)
                    Icon(Icons.star, size: 13, color: c.verm),
                  const Spacer(),
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
                      'how likely this word is picked · not a promise of which day',
                      style: TextStyle(
                        fontFamily: TypeScale.sans,
                        fontSize: 10.5,
                        color: c.ink3,
                      ),
                    ),
                  ),
                  _Star(lemma: w.lemma, starred: w.starred, onStar: onStar),
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
          onTap: () => onOpen(w.lemma),
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
                Text(
                  '${w.encounters}×',
                  style: TextStyle(
                    fontFamily: TypeScale.mono,
                    fontSize: 10.5,
                    color: c.ink3,
                  ),
                ),
                const SizedBox(width: 8),
                _Star(lemma: w.lemma, starred: w.starred, onStar: onStar),
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
  });

  final String lemma;
  final bool starred;
  final void Function(String lemma, bool starred) onStar;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Tooltip(
      message: starred
          ? 'stop asking for this one'
          : 'ask for this one again · free, and rewrites nothing',
      child: SizedBox(
        width: 32,
        height: 28,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => onStar(lemma, !starred),
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