// A plan must say WHAT it is about before the reader is asked to pay for it.
//
// The queue used to install free plans with no subject at all: the card said
// `Anything`, and both `Change it` and `Draw another plan` opened onto a blank
// decision. A reader cannot choose between two plans they cannot see, and
// "change it" is meaningless when there is nothing on the card to change.
//
// This is a LOCAL, free catalogue of concrete subjects. It is deliberately not
// a model call: a plan that costs money to preview is not a free plan, and the
// cost line on the card says `free`. The writer still gets the reader's whole
// reading plan (style, avoid, length) — this only supplies the subject that the
// card can show in advance.

import 'dart:math';

/// Concrete, self-contained article subjects.
///
/// Each one is a sentence the writer can act on without further context, and
/// each is the kind of surprising-but-true explanation the app is for. They are
/// deliberately specific: "Science" is not a subject a reader can decide about,
/// and "Why fresh snow squeaks" is.
const List<String> kSuggestedSubjects = <String>[
  'Why a mirror never swaps your left and right',
  'How a vending machine tells a fake coin from a real one',
  'Why fresh snow squeaks under your boots',
  'How a compass finds north without a battery',
  'Why some sounds make your teeth feel strange',
  'How a thermos keeps tea hot for a whole day',
  'Why the sea looks blue even under a grey sky',
  'How a zipper closes without leaving a gap',
  'Why a spinning top refuses to fall over',
  'How noise-cancelling headphones guess what to cancel',
  'Why a microwave heats the edge of a plate first',
  'Why old books smell sweet',
  'How a bicycle stays upright once it moves',
  'Why your voice sounds wrong in a recording',
  'How a seed knows which way is up',
  'Why soap makes water feel slippery',
  'How a barcode is read in a single blink',
  'Why train tracks click under the wheels',
  'How a fridge decides when to stop cooling',
  'Why some ice is clear and some is white',
  'How a touchscreen knows where your finger is',
  'Why a kettle whistles before it boils',
  'How a spider builds a web without a plan',
  'Why a steel ship can float',
  'How an airplane wing turns speed into lift',
  'Why your ears pop in a fast lift',
  'Why a candle flame casts almost no shadow',
  'How a key opens only its own lock',
  'Why bread goes stale faster in the fridge',
  'How a fly lands on the ceiling upside down',
  'Why the sky turns red at sunset',
  'How a speed camera measures speed in the dark',
  'Why a rubber band gets warm when stretched',
  'How a supermarket keeps lettuce fresh for a week',
  'Why a spinning coin hums before it stops',
  'How a shadow can be sharper than the object',
  'How a smart speaker hears its name in a noisy room',
  'Why a wheel is round and not square',
  'How a ship\'s anchor holds against a current',
  'Why a guitar string sounds different when pressed',
  'How a plant leans towards a window',
  'Why a clay pot keeps water cool',
  'How a fountain pushes water into the air',
  'Why a bathroom mirror fogs on one side first',
  'How a simple radio picks one station out of thousands',
  'Why a paper straw goes soft but a plastic one does not',
  'How a streetlight knows it is dark',
  'Why a spinning egg stands up when it slows',
  'How a submarine sinks and rises without moving',
  'Why a cut apple turns brown so quickly',
  'How a fire alarm smells smoke instead of fire',
  'Why a camera flash makes eyes red',
  'How a plane door stays shut in the air',
  'Why a hot cup feels colder than a metal spoon',
  'How a bee finds its way home',
  'Why a flag ripples even in a steady wind',
  'Why a straw in water looks broken',
  'How a dish antenna focuses a signal',
  'Why a balloon shrinks in the cold',
];

/// Draws subjects for new plans without repeating one the reader just saw.
///
/// The memory is per process, which is the right scope: it exists to stop two
/// cards on screen from saying the same thing, not to be a history the reader
/// never asked for. [avoid] is for the caller's own exclusions — the other
/// planned cards, and the plan a reroll is replacing.
class SubjectSuggester {
  SubjectSuggester({Random? random}) : _random = random ?? Random();

  final Random _random;
  final List<String> _recent = <String>[];
  static const int _memory = 16;

  /// [preferred] is tried FIRST: today's headlines are fresher than a fixed
  /// catalogue, and the app already has them for free when the news source is
  /// configured. The built-in list is the offline / no-key fallback and the
  /// floor that keeps a plan card from ever being blank.
  String next({
    Iterable<String> avoid = const <String>[],
    Iterable<String> preferred = const <String>[],
  }) {
    final Set<String> blocked = <String>{...avoid, ..._recent};
    List<String> pool = <String>[
      for (final String s in preferred)
        if (s.trim().isNotEmpty && !blocked.contains(s.trim())) s.trim(),
    ];
    if (pool.isEmpty) {
      pool = <String>[
        for (final String s in kSuggestedSubjects)
          if (!blocked.contains(s)) s,
      ];
    }
    // Every subject was just used (only possible after dozens of draws in one
    // session). Forget the short-term memory rather than returning a duplicate
    // from the caller's avoid list.
    if (pool.isEmpty) {
      _recent.clear();
      pool = <String>[
        for (final String s in kSuggestedSubjects)
          if (!avoid.contains(s)) s,
      ];
    }
    if (pool.isEmpty) pool = List<String>.of(kSuggestedSubjects);

    final String pick = pool[_random.nextInt(pool.length)];
    _recent.add(pick);
    if (_recent.length > _memory) _recent.removeAt(0);
    return pick;
  }
}
