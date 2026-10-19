// Attaching photographs to a write.
//
// The habit this serves: you meet a good sentence on a poster, or a scene worth
// describing, or you are halfway through memorising a word list in another app
// and you take a screenshot. All three are two seconds with a camera and
// impossible with a keyboard. So the instruction is not only words any more.
//
// THREE THINGS THIS SHEET DECIDES, and the order is the design:
//
//   1. WHERE THE PICTURES COME FROM. Gallery or camera. Both, always — a word
//      list is a screenshot in the gallery, a good sentence on a poster is a
//      photograph you are about to take.
//   2. WHAT HAPPENS TO THEM. Every one is shrunk to under 2 MB before it is
//      kept, and the sheet says so with the real numbers. A reader who watches
//      "3.8 MB → 480 KB" appear has learned where their data went; one who sees
//      a picture appear and disappear has learned nothing.
//   3. WHAT THE PICTURES ARE FOR. A sentence to be written about, a scene, or a
//      word list to be USED. The reader is asked, because the answer changes the
//      article completely and guessing it wrong wastes the tap they are about to
//      pay for.
//
// WHAT THIS SHEET DOES NOT DO: save anything. A picture instruction belongs to
// the ONE write it was attached to. There is no list of saved pictures, no
// gallery, nothing that outlives the article — the reader already has their
// photographs in their photo app, and a second copy inside this one would be a
// table of blobs nobody can search.
//
// It is also free, and says so in jade. Attaching is choosing; writing is the
// tap that costs.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/texture.dart' show Hairline;
import '../../data/shrink.dart';
import '../../domain/picture.dart';

/// What the reader is attaching, in their words. Drives the prompt.
enum PictureIntent {
  /// A sentence met somewhere. The article is about its IDEA.
  sentence,

  /// A scene worth describing. The article is about the THING.
  scene,

  /// A word list from another app. The article USES those words.
  wordList,
}

extension PictureIntentX on PictureIntent {
  String get label => switch (this) {
        PictureIntent.sentence => 'A good sentence',
        PictureIntent.scene => 'A scene',
        PictureIntent.wordList => 'A word list',
      };

  /// The one line under the label. Says what will happen, because the three
  /// outcomes are different articles and the reader is the only one who knows
  /// which one they want.
  String get note => switch (this) {
        PictureIntent.sentence =>
          'the article is about what it says — not its words',
        PictureIntent.scene => 'the article describes what is in the picture',
        PictureIntent.wordList =>
          'the article uses those words in real sentences',
      };

  /// The word for the log and the card.
  String get short => switch (this) {
        PictureIntent.sentence => 'a sentence',
        PictureIntent.scene => 'a scene',
        PictureIntent.wordList => 'a word list',
      };
}

/// What the sheet hands back. Pictures already shrunk, plus the intent.
class PictureRequest {
  const PictureRequest({required this.pictures, required this.intent});

  final List<Picture> pictures;
  final PictureIntent intent;

  bool get isEmpty => pictures.isEmpty;
}

/// How many the picker may take in one go. Matches [kMaxPictures] — the sheet
/// enforces the same ceiling the domain does, so the reader is stopped before
/// they have picked seven rather than after.
const int _kPickLimit = kMaxPictures;

class PictureSheet extends StatefulWidget {
  const PictureSheet({
    super.key,
    required this.intent,
    this.canSeePictures = true,
  });

  /// What the reader already said this is for, when they said it. Null the first
  /// time, and then the question is asked rather than assumed.
  final PictureIntent? intent;

  /// False when the chosen writer cannot see pictures. The sheet still opens —
  /// a reader who tapped the camera deserves to know why it will not work, and
  /// a sheet that refuses to appear is a sheet that teaches nothing.
  final bool canSeePictures;

  @override
  State<PictureSheet> createState() => _PictureSheetState();
}

class _PictureSheetState extends State<PictureSheet> {
  final ImagePicker _picker = ImagePicker();
  final List<Picture> _pictures = <Picture>[];

  PictureIntent? _intent;
  bool _busy = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _intent = widget.intent;
  }

  bool get _full => _pictures.length >= _kPickLimit;

  /// Take more pictures. Gallery first, then camera — the sheet says which one
  /// it is about to open, so a reader who wanted the other one is not surprised.
  ///
  /// The shrink happens BEFORE the sheet returns anything, so a picture that
  /// cannot be read or cannot be made small enough is reported here rather than
  /// discovered halfway through a paid write.
  Future<void> _pick(ImageSource source) async {
    if (_full || _busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      // HONOUR THE SOURCE. The old code always called `pickMultiImage` (the
      // gallery) and only fell back to the camera when the gallery came back
      // empty, so "Take one" opened the photo picker first. On a phone with no
      // gallery app it looked like a dead button. One source, one call.
      final List<XFile> picked;
      if (source == ImageSource.camera) {
        final XFile? shot = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 92,
        );
        picked = shot == null ? <XFile>[] : <XFile>[shot];
      } else {
        picked = await _picker.pickMultiImage(
          limit: _kPickLimit - _pictures.length,
          imageQuality: 92,
        );
      }
      if (picked.isEmpty) return;

      for (final XFile f in picked) {
        if (_pictures.length >= _kPickLimit) break;
        final Picture? p = await shrink(f.path);
        if (p == null) {
          setState(() => _problem =
              'one of those could not be read as a picture. It was skipped.');
          continue;
        }
        setState(() => _pictures.add(p));
      }
    } catch (e) {
      setState(() => _problem = 'the pictures could not be opened · $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remove(int i) => setState(() => _pictures.removeAt(i));

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
            'Write it from a picture',
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
            'Up to $_kPickLimit pictures. Attaching is free — the paid step is '
            'still Write it.',
            style: TextStyle(
              fontFamily: TypeScale.serif,
              fontSize: 13,
              height: 1.6,
              color: c.ink3,
            ),
          ),

          // The refusal, stated plainly and BEFORE any money moves. A reader who
          // picked a text-only writer is told here, with the alternatives named,
          // rather than by a 400 they have to interpret.
          if (!widget.canSeePictures) ...<Widget>[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.verm.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.verm.withValues(alpha: 0.35)),
              ),
              child: Text(
                'This writer cannot see pictures. Pick MiMo or OpenAI in '
                'Settings and come back, or write it without them.',
                style: TextStyle(
                  fontFamily: TypeScale.serif,
                  fontSize: 13.5,
                  height: 1.55,
                  color: c.ink,
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),
          const SectionLabel('What are they?'),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              for (final PictureIntent i in PictureIntent.values)
                Pill(
                  i.label,
                  mono: false,
                  color: _intent == i ? c.ink : null,
                  background: _intent == i ? c.surface : null,
                  borderColor: _intent == i ? c.verm : null,
                  onTap: () => setState(() => _intent = i),
                ),
            ],
          ),
          if (_intent != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _intent!.note,
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 12.5,
                height: 1.55,
                color: c.ink3,
              ),
            ),
          ],

          const SizedBox(height: 18),
          const SectionLabel('The pictures'),
          Row(
            children: <Widget>[
              Expanded(
                child: Btn(
                  // Short enough to fit half the sheet beside "Take one".
                  label: _busy ? 'Reading them…' : 'From gallery',
                  icon: '▤',
                  dense: true,
                  busy: _busy,
                  primary: false,
                  onPressed: _busy || _full
                      ? null
                      : () => _pick(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: Gap.xs),
              // Expanded, BECAUSE `Btn` IS `SizedBox(width: double.infinity)`.
              // As a bare child of a Row it was given an infinite width and the
              // whole sheet failed layout — the barrier appeared over the queue
              // and the sheet itself painted as nothing. This is the bug behind
              // "the picture button does not work".
              Expanded(
                child: Btn(
                  label: 'Take one',
                  icon: '◉',
                  dense: true,
                  busy: _busy,
                  primary: false,
                  onPressed: _busy || _full
                      ? null
                      : () => _pick(ImageSource.camera),
                ),
              ),
            ],
          ),

          if (_pictures.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            for (int i = 0; i < _pictures.length; i++)
              _row(c, _pictures[i], () => _remove(i)),
          ],

          if (_full) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'That is the $_kPickLimit this instruction can carry.',
              style: TextStyle(
                fontFamily: TypeScale.mono,
                fontSize: 10.5,
                color: c.ink3,
              ),
            ),
          ],

          if (_problem != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _problem!,
              style: TextStyle(
                fontFamily: TypeScale.serif,
                fontSize: 12.5,
                height: 1.55,
                color: c.verm,
              ),
            ),
          ],

          const SizedBox(height: 18),
          Hairline(color: c.hair),
          const SizedBox(height: 12),
          _cost(c),

          const SizedBox(height: 14),
          Btn(
            label: _pictures.isEmpty
                ? 'Pick a picture first'
                : (_intent == null
                    ? 'Choose what they are above'
                    : 'Attach ${_pictures.length} · then Write it'),
            primary: true,
            // THE EMPTY STATE IS A BUTTON, not a dead control. "Pick a
            // picture first" used to be permanently disabled, which is a
            // sentence describing an action the reader cannot take from the
            // place that says it. It now opens the gallery itself; the camera
            // has its own button beside it.
            onPressed: _busy
                ? null
                : _pictures.isEmpty
                    ? () => _pick(ImageSource.gallery)
                    // A picture with no intent is a picture the model has to
                    // guess about, and guessing wrong costs the whole write.
                    : (_intent == null
                        ? null
                        : () => Navigator.of(context).pop(
                              PictureRequest(
                                pictures: List<Picture>.of(_pictures),
                                intent: _intent!,
                              ),
                            )),
          ),
        ],
      ),
    );
  }

  /// One attached picture, with its real before-and-after size.
  Widget _row(Palette c, Picture p, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          // The thumbnail, from the bytes already in memory. Not a file read:
          // the file is a cache entry that may be gone by the next frame.
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              p.bytes,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (BuildContext ctx, Object err, StackTrace? st) =>
                  Container(
                    width: 44,
                    height: 44,
                    color: c.paperSunk,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  Picture.size(p.bytes.lengthInBytes),
                  style: TextStyle(
                    fontFamily: TypeScale.mono,
                    fontSize: 11.5,
                    color: c.ink,
                  ),
                ),
                if (p.wasResized)
                  Text(
                    'was ${Picture.size(p.originalBytes)} · made smaller here',
                    style: TextStyle(
                      fontFamily: TypeScale.mono,
                      fontSize: 10,
                      color: c.ink3,
                    ),
                  )
                else
                  Text(
                    'already small enough · sent as it was',
                    style: TextStyle(
                      fontFamily: TypeScale.mono,
                      fontSize: 10,
                      color: c.ink3,
                    ),
                  ),
              ],
            ),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text('✕',
                  style: TextStyle(fontSize: 13, color: c.ink3)),
            ),
          ),
        ],
      ),
    );
  }

  /// The cost line. JADE, never vermilion: this sheet spends nothing.
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
