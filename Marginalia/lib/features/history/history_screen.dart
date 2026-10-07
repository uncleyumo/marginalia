// The retrospective. Nothing here is actionable.
//
// DESIGN is emphatic: this screen exists to be looked at and then left alone.
// There is no way to mark a day, no streak, no "you did well", and nothing to
// tap except a date you want to read. A history that could be edited is a
// scoreboard, and a scoreboard changes what you do in the present in order to
// look good in the past — which is the opposite of what this app is for.
//
// *Most revisited* sits at the bottom rather than the top on purpose: it is the
// answer to a question the reader did not know they had, so it should not be the
// first thing they see.

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/back_label.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/texture.dart';

/// One day's total. Computed by a GROUP BY over the same rows the calendar and
/// *Most revisited* read — never a stored summary that could disagree.
class DayCell {
  const DayCell({required this.day, required this.reads, required this.listens});

  final int day;
  final int reads;
  final int listens;

  bool get hasAnything => reads > 0 || listens > 0;
  int get touches => reads + listens;
}

class RevisitedRow {
  const RevisitedRow({
    required this.title,
    required this.reads,
    required this.listens,
  });

  final String title;
  final int reads;
  final int listens;

  int get touches => reads + listens;
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({
    super.key,
    required this.year,
    required this.month,
    required this.today,
    required this.cells,
    required this.mostRevisited,
    required this.onOpenDay,
    required this.onBack,
  });

  final int year;
  final int month;

  /// The current day of month, 1-based. Days after it render blank — the design
  /// has no future state to show, and inventing one would be a promise.
  final int today;

  final List<DayCell> cells;
  final List<RevisitedRow> mostRevisited;
  final void Function(int day) onOpenDay;

  /// The header label is a button, so it needs somewhere to go.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return PageScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.gutter, 8, Gap.gutter, 30),
        children: <Widget>[
          Row(
            children: <Widget>[
              BackLabel(label: '‹ Queue', onTap: onBack),
              const Spacer(),
              Text(
                '$year · ${_monthName(month)}',
                style: TextStyle(
                  fontFamily: TypeScale.mono,
                  fontSize: 10.5,
                  color: c.ink3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Eyebrow('History · only ever looked at'),
          Text('You read on these days', style: context.texts.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Nothing here can be marked, scored or undone.',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: c.ink3,
            ),
          ),
          const SizedBox(height: 20),
          _calendar(context, c),
          const SizedBox(height: 26),
          const SectionLabel('Most revisited'),
          const SizedBox(height: 4),
          if (mostRevisited.isEmpty)
            Text(
              'Read one thing twice and it shows up here.',
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 13.5,
                height: 1.6,
                color: c.ink3,
              ),
            )
          else
            ...mostRevisited.map((RevisitedRow r) => _revisitRow(c, r)),
        ],
      ),
    );
  }

  Widget _calendar(BuildContext context, Palette c) {
    final int daysInMonth = DateTime(year, month + 1, 0).day;
    // Monday-first. A calendar starting on Sunday reads as a chore.
    final int firstWeekday = DateTime(year, month, 1).weekday % 7;

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            for (final String d in const <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: TextStyle(
                      fontFamily: TypeScale.mono,
                      fontSize: 10,
                      color: c.ink3,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.05,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: firstWeekday + daysInMonth,
          itemBuilder: (BuildContext ctx, int i) {
            if (i < firstWeekday) return const SizedBox.shrink();
            final int day = i - firstWeekday + 1;
            if (day > daysInMonth) return const SizedBox.shrink();
            final DayCell? cell = _cellFor(day);
            if (day > today) {
              return _futureCell(c, day);
            }
            return _dayCell(c, day, cell);
          },
        ),
      ],
    );
  }

  DayCell? _cellFor(int day) {
    for (final DayCell x in cells) {
      if (x.day == day) return x;
    }
    return null;
  }

  /// A day with nothing on it: present but quiet. The reader can see that the
  /// day existed and chose nothing, which is different from the day not being
  /// there.
  Widget _dayCell(Palette c, int day, DayCell? cell) {
    final bool any = cell?.hasAnything ?? false;
    return Material(
      color: any ? c.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: any ? () => onOpenDay(day) : null,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: any ? c.hair : c.rule.withValues(alpha: 0.4)),
          ),
          child: Stack(
            children: <Widget>[
              Center(
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontFamily: TypeScale.mono,
                    fontSize: 11.5,
                    color: any ? c.ink : c.ink3,
                  ),
                ),
              ),
              // the count, in the corner, small — a number you can read at a
              // glance and not a chart you are meant to study
              if (any)
                Positioned(
                  top: 2,
                  right: 3,
                  child: Text(
                    '${cell!.touches}',
                    style: TextStyle(
                      fontFamily: TypeScale.mono,
                      fontSize: 8.5,
                      color: c.jade,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _futureCell(Palette c, int day) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: c.rule.withValues(alpha: 0.18)),
      ),
      child: Center(
        child: Text(
          '$day',
          style: TextStyle(
            fontFamily: TypeScale.mono,
            fontSize: 11.5,
            color: c.ink3.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }

  /// Two hatched bars, read and heard, on a shared scale.
  ///
  /// The bars are engraved rather than filled so they read as a record rather
  /// than a progress meter — there is nothing here to make progress against.
  Widget _revisitRow(Palette c, RevisitedRow r) {
    final int max = mostRevisited.isEmpty ? 1 : mostRevisited.first.touches;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Text(
              r.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 14.5,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _bar(c, r.reads, max, c.jade, '${r.reads}×'),
          const SizedBox(width: 6),
          _bar(c, r.listens, max, c.lamp, '${r.listens}×'),
        ],
      ),
    );
  }

  Widget _bar(Palette c, int value, int max, Color color, String label) {
    return SizedBox(
      width: 74,
      child: Row(
        children: <Widget>[
          Expanded(
            child: HatchedBar(
              fraction: max == 0 ? 0 : value / max,
              color: color,
              height: 6,
            ),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: 26,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: TypeScale.mono,
                fontSize: 10,
                color: c.ink3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _monthName(int m) => const <String>[
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ][m - 1];
}

/// One day in detail. Recorded, never graded.
class DaySheet extends StatelessWidget {
  const DaySheet({
    super.key,
    required this.label,
    required this.reads,
    required this.listens,
    required this.articles,
    required this.minutes,
  });

  final String label;
  final int reads;
  final int listens;
  final List<({String title, int reads, int listens})> articles;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    // CONTENT ONLY — the frame and its single Close belong to AppSheet.show.
    // This used to draw its own AppSheetFrame inside a sheet, which is where the
    // second Close button came from.
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sheetPad, 0, Gap.sheetPad, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _stat(c, 'Times read all the way through', reads),
          _stat(c, 'Times played or listened', listens),
          _stat(c, 'Articles touched', articles.length),
          _stat(c, 'Minutes', minutes),
          const SizedBox(height: 18),
          Text(
            'Which ones',
            style: TextStyle(
              fontFamily: TypeScale.mono,
              fontSize: 10,
              letterSpacing: 0.14,
              color: c.ink3,
            ),
          ),
          const SizedBox(height: 8),
          if (articles.isEmpty)
            Text(
              'Nothing was read or heard on this day.',
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 14,
                color: c.ink3,
              ),
            )
          else
            for (final ({String title, int reads, int listens}) a in articles)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        a.title,
                        style: TextStyle(
                          fontFamily: TypeScale.serif,
                          fontSize: 14.5,
                          color: c.ink,
                        ),
                      ),
                    ),
                    if (a.reads > 0)
                      Text('read ${a.reads}×',
                          style: TextStyle(
                            fontFamily: TypeScale.mono,
                            fontSize: 10.5,
                            color: c.ink3,
                          )),
                    if (a.listens > 0)
                      Text('heard ${a.listens}×',
                          style: TextStyle(
                            fontFamily: TypeScale.mono,
                            fontSize: 10.5,
                            color: c.ink3,
                          )),
                  ],
                ),
              ),
          const SizedBox(height: 14),
          Text(
            'Recorded, not graded. An article stays in the queue after you '
            'read it once, so coming back here is how you find it again.',
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

  Widget _stat(Palette c, String label, int value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: TypeScale.sans,
                fontSize: 13,
                color: c.ink2,
              ),
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              fontFamily: TypeScale.mono,
              fontSize: 13,
              color: c.ink,
            ),
          ),
        ],
      ),
    );
  }
}