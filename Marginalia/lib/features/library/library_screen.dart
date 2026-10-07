// The shelf.
//
// Every row here is either an article the reader has met or one still in the
// queue. Nothing is ever hidden, and a DELETED article is not an exception: it
// stays on this list, struck through, still counted.
//
// That is the visible half of invariant 4. The invisible half is that freeing
// an article's space never touches reads or listens, which is why the row can
// keep saying `5× read` while its size reads `—`.
//
// The list is DERIVED, never stored: `shelf()` in lib/domain/library.dart merges
// the ledger with the live queue by title. There is no library table, so there is
// no second copy of the truth to fall out of sync with the counters.

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/back_label.dart';
import '../../core/widgets/primitives.dart';
import '../queue/queue_card.dart' show StorageLine;
import '../../domain/library.dart';
import '../../domain/queue.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.rows,
    required this.usedKb,
    required this.freedKb,
    required this.goneCount,
    required this.onOpen,
    required this.onFree,
    required this.onBack,
  });

  final List<ShelfRow> rows;
  final int usedKb;
  final int freedKb;
  final int goneCount;
  final void Function(ShelfRow row) onOpen;

  /// Only ever called for a row that passed [canFreeSpace], and the handler
  /// re-checks: a live card has nothing behind it to open.
  final void Function(ShelfRow row) onFree;

  /// The header label is a button, so it needs somewhere to go.
  final VoidCallback onBack;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _search = TextEditingController();
  LibraryFilter _filter = LibraryFilter.all;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final List<ShelfRow> shown = widget.rows
        .where((ShelfRow r) => _filter.matches(r))
        .where((ShelfRow r) {
          final String q = _search.text.trim().toLowerCase();
          return q.isEmpty ||
              r.title.toLowerCase().contains(q) ||
              r.topic.toLowerCase().contains(q);
        })
        .toList();

    return PageScaffold(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, 8, Gap.gutter, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    BackLabel(label: '‹ Queue', onTap: widget.onBack),
                    const Spacer(),
                    Text(
                      '${widget.rows.length} articles',
                      style: TextStyle(
                        fontFamily: TypeScale.mono,
                        fontSize: 10.5,
                        color: c.ink3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Eyebrow('Library · everything you have met'),
                Text('Your shelf', style: context.texts.titleLarge),
                const SizedBox(height: 16),
                _searchField(c),
                const SizedBox(height: 10),
                _filters(c),
                const SizedBox(height: 16),
                StorageLine(
                  usedKb: widget.usedKb,
                  freedKb: widget.freedKb,
                  goneCount: widget.goneCount,
                ),
                const SizedBox(height: 6),
                if (widget.freedKb > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'their read counts are still counted above',
                      style: TextStyle(
                        fontFamily: TypeScale.sans,
                        fontSize: 11,
                        color: c.ink3,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? _empty(context, c)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        Gap.gutter, 0, Gap.gutter, 28),
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 7),
                    itemBuilder: (BuildContext ctx, int i) => ShelfRowView(
                      row: shown[i],
                      onOpen: () => widget.onOpen(shown[i]),
                      onFree: () => widget.onFree(shown[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(Palette c) {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: _search,
        style: TextStyle(
          fontFamily: TypeScale.serif,
          fontSize: 15,
          color: c.ink,
        ),
        decoration: InputDecoration(
          hintText: 'title or topic',
          hintStyle: TextStyle(
            fontFamily: TypeScale.serif,
            fontSize: 14,
            color: c.ink3,
          ),
          prefixIcon: Icon(Icons.search, size: 17, color: c.ink3),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 38, minHeight: 38),
          filled: true,
          fillColor: c.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
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
      ),
    );
  }

  /// The five filters, each a QUESTION rather than a state to manage.
  Widget _filters(Palette c) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final LibraryFilter f in LibraryFilter.values)
          Pill(
            f.label,
            mono: false,
            color: _filter == f ? c.paper : c.ink3,
            background: _filter == f ? c.verm : null,
            borderColor: _filter == f ? c.verm : null,
            onTap: () => setState(() => _filter = f),
          ),
      ],
    );
  }

  Widget _empty(BuildContext context, Palette c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _filter == LibraryFilter.all
                  ? 'Nothing here yet'
                  : 'Nothing under “${_filter.label}”',
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 16,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The shelf fills as you read. An article stays here for good.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 13.5,
                height: 1.6,
                color: c.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One shelf row: a title line, a meta line, counts in a fixed column, and the
/// state on the spine.
class ShelfRowView extends StatelessWidget {
  const ShelfRowView({
    super.key,
    required this.row,
    required this.onOpen,
    required this.onFree,
  });

  final ShelfRow row;
  final VoidCallback onOpen;
  final VoidCallback onFree;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final bool canFree = canFreeSpace(
      isLiveInQueue: row.isLive,
      isAlreadyGone: row.isGone,
    );

    return Material(
      color: row.isGone ? Colors.transparent : c.surface,
      borderRadius: Radii.cardAll,
      child: InkWell(
        onTap: row.isGone ? null : onOpen,
        borderRadius: Radii.cardAll,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: Radii.cardAll,
            border: Border.all(color: c.hair),
          ),
          padding: const EdgeInsets.fromLTRB(13, 11, 11, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // The spine carries the state: jade live, hair plain, dashed gone.
              _Spine(
                live: row.isLive,
                gone: row.isGone,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      row.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: TypeScale.serif,
                        fontSize: 15.5,
                        // A freed row is struck through, not greyed out: grey
                        // reads as disabled, and this row still counts.
                        decoration: row.isGone
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: c.ink3,
                        color: row.isGone ? c.ink3 : c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _meta(c),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _counts(c),
              const SizedBox(width: 6),
              // A live card has no free button AT ALL, not a disabled one: the
              // design says it is what it is, not "you cannot do that right now".
              if (canFree)
                _FreeBtn(onTap: onFree)
              else
                const SizedBox(width: 30, height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(Palette c) {
    final List<String> parts = <String>[];
    if (row.isGone) {
      parts.add('deleted · text and audio removed');
    } else if (row.isLive) {
      parts.add('in the queue');
      if (row.meta.isNotEmpty) parts.add(row.meta);
    } else {
      parts.add(row.topic.isEmpty ? 'archived' : row.topic);
      if (row.meta.isNotEmpty) parts.add(row.meta);
    }
    if (!row.isGone && row.reads == 0 && row.listens > 0) {
      parts.add('heard, never read');
    }

    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: TypeScale.sans,
        fontSize: 11,
        color: row.isGone ? c.ink3 : (parts.length > 2 ? c.lamp : c.ink3),
      ),
    );
  }

  Widget _counts(Palette c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          '${row.reads}×',
          style: TextStyle(
            fontFamily: TypeScale.mono,
            fontSize: 11,
            color: row.reads > 0 ? c.ink2 : c.ink3,
          ),
        ),
        Text(
          'read',
          style: TextStyle(
            fontFamily: TypeScale.sans,
            fontSize: 9.5,
            color: c.ink3,
          ),
        ),
      ],
    );
  }
}

/// The spine. Shape and stroke, not colour alone.
class _Spine extends StatelessWidget {
  const _Spine({required this.live, required this.gone});

  final bool live;
  final bool gone;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return SizedBox(
      width: 3,
      height: 34,
      child: CustomPaint(
        painter: _SpinePainter(
          color: gone ? c.rule : (live ? c.jade : c.hair),
          dashed: gone,
        ),
      ),
    );
  }
}

class _SpinePainter extends CustomPainter {
  _SpinePainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = size.width
      ..strokeCap = StrokeCap.butt;
    if (!dashed) {
      canvas.drawLine(Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height), paint);
      return;
    }
    // A dashed spine for a freed row: present, but not there any more.
    const int dashes = 5;
    final double seg = size.height / (dashes * 2 - 1);
    for (int i = 0; i < dashes; i++) {
      final double y = i * seg * 2;
      canvas.drawLine(
          Offset(size.width / 2, y), Offset(size.width / 2, y + seg), paint);
    }
  }

  @override
  bool shouldRepaint(_SpinePainter old) =>
      old.color != color || old.dashed != dashed;
}

class _FreeBtn extends StatelessWidget {
  const _FreeBtn({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Tooltip(
      message: 'Free the space · the counts stay',
      child: SizedBox(
        width: 30,
        height: 30,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Center(
              child: Text(
                '⌫',
                style: TextStyle(
                  fontFamily: TypeScale.sans,
                  fontSize: 14,
                  color: c.ink3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The confirmation. Two colour-coded columns — what GOES and what STAYS.
///
/// DESIGN's reason for the two columns: "delete" alone would be a lie of
/// omission, because the app has promised repeatedly that nothing is ever
/// deleted and now has a button that says delete. So the trade is shown before
/// it happens, in the reader's own numbers.
class FreeSpaceSheet extends StatelessWidget {
  const FreeSpaceSheet({super.key, required this.row, required this.onConfirm});

  final ShelfRow row;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    final FreeSpaceTrade trade = FreeSpaceTrade(
      kilobytes: row.freedKilobytes,
      reads: row.reads,
      listens: row.listens,
    );

    // CONTENT ONLY. The frame — grab handle, header, one Close — is applied by
    // AppSheet.show, and a body that draws its own frame produces two grab
    // handles and two Close buttons stacked on top of each other.
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sheetPad, 0, Gap.sheetPad, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            row.title,
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _column(
                    c, 'Goes', trade.goes, trade.freed, c.verm, c.vermWash),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _column(c, 'Stays', trade.stays, trade.staysNote, c.jade,
                    c.jadeWash),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            trade.why,
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 14,
              height: 1.68,
              color: c.ink2,
            ),
          ),
          const SizedBox(height: 20),
          Btn(
            label: 'Free it · the counts stay',
            onPressed: onConfirm,
          ),
        ],
      ),
    );
  }

  Widget _column(
    Palette c,
    String label,
    List<String> items,
    String foot,
    Color accent,
    Color wash,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: TypeScale.mono,
              fontSize: 10,
              letterSpacing: 0.16,
              color: accent,
            ),
          ),
          const SizedBox(height: 8),
          for (final String i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                i,
                style: TextStyle(
                  fontFamily: TypeScale.sans,
                  fontSize: 13,
                  color: c.ink,
                ),
              ),
            ),
          const SizedBox(height: 5),
          Text(
            foot,
            style: TextStyle(
              fontFamily: TypeScale.sans,
              fontSize: 11,
              height: 1.45,
              color: c.ink3,
            ),
          ),
        ],
      ),
    );
  }
}