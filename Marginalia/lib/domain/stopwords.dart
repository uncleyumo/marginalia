// Function words are not vocabulary.
//
// Every word in an article is tappable, and a tap is what records a word in
// "Your words". That is the right mechanic, but it means `the`, `and`, `for`
// and `has` can end up in a list whose whole purpose is "words worth meeting
// again". They were met — they are just not worth reviewing: a reader who has
// got this far already knows them, and a list padded with them hides the words
// that actually need another showing.
//
// This list is deliberately FUNCTION words only: articles, determiners,
// pronouns, prepositions, conjunctions, auxiliaries and contractions. Ordinary
// but useful vocabulary (`get`, `make`, `good`, `people`) is NOT here — those
// are exactly the words a learner revisits.
const Set<String> kStopwords = <String>{
  // articles and determiners
  'a', 'an', 'the', 'this', 'that', 'these', 'those', 'each', 'every',
  'either', 'neither', 'some', 'any', 'no', 'all', 'both', 'few', 'many',
  'much', 'more', 'most', 'less', 'least', 'another', 'other', 'others',
  'such', 'what', 'whatever', 'which', 'whichever', 'whose',

  // pronouns
  'i', 'me', 'my', 'mine', 'myself',
  'you', 'your', 'yours', 'yourself', 'yourselves',
  'he', 'him', 'his', 'himself',
  'she', 'her', 'hers', 'herself',
  'it', 'its', 'itself',
  'we', 'us', 'our', 'ours', 'ourselves',
  'they', 'them', 'their', 'theirs', 'themselves',
  'who', 'whom', 'whoever', 'whomever',
  'someone', 'somebody', 'something', 'anyone', 'anybody', 'anything',
  'everyone', 'everybody', 'everything', 'nobody', 'nothing', 'none',
  'one', 'ones',

  // prepositions
  'about', 'above', 'across', 'after', 'against', 'along', 'among', 'around',
  'at', 'before', 'behind', 'below', 'beneath', 'beside', 'between', 'beyond',
  'by', 'down', 'during', 'for', 'from', 'in', 'inside', 'into', 'near',
  'of', 'off', 'on', 'onto', 'out', 'outside', 'over', 'past', 'per',
  'since', 'through', 'throughout', 'to', 'toward', 'towards', 'under',
  'until', 'up', 'upon', 'with', 'within', 'without',

  // conjunctions and linking adverbs
  'and', 'but', 'or', 'nor', 'so', 'yet', 'if', 'unless', 'because',
  'as', 'than', 'then', 'though', 'although', 'while', 'whereas', 'whether',
  'when', 'whenever', 'where', 'wherever', 'why', 'how', 'however',
  'therefore', 'thus', 'hence', 'also', 'too', 'very', 'just', 'only',
  'even', 'still',

  // auxiliaries and the copula
  'am', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
  'have', 'has', 'had', 'having',
  'do', 'does', 'did', 'done', 'doing',
  'will', 'would', 'shall', 'should', 'can', 'could', 'may', 'might',
  'must', 'ought',

  // particles and placeholders
  'not', 'yes', 'there', 'here', 'whereby', 'via',
  'once', 'twice', 'mr', 'mrs', 'ms', 'dr', 'etc',

  // contractions (the tokenizer keeps the apostrophe)
  "i'm", "i've", "i'll", "i'd",
  "you're", "you've", "you'll", "you'd",
  "he's", "he'll", "he'd",
  "she's", "she'll", "she'd",
  "it's", "it'll", "it'd",
  "we're", "we've", "we'll", "we'd",
  "they're", "they've", "they'll", "they'd",
  "that's", "there's", "here's", "what's", "who's", "where's", "how's",
  "isn't", "aren't", "wasn't", "weren't",
  "don't", "doesn't", "didn't",
  "can't", 'cannot', "couldn't", "won't", "wouldn't", "shouldn't",
  "haven't", "hasn't", "hadn't", "mustn't", "let's",
  'i’m', 'i’ve', 'i’ll', 'i’d', 'you’re', 'you’ve', 'you’ll', 'you’d',
  'he’s', 'he’ll', 'he’d', 'she’s', 'she’ll', 'she’d', 'it’s', 'it’ll',
  'it’d', 'we’re', 'we’ve', 'we’ll', 'we’d', 'they’re', 'they’ve',
  'they’ll', 'they’d', 'that’s', 'there’s', 'here’s', 'what’s', 'who’s',
  'isn’t', 'aren’t', 'wasn’t', 'weren’t', 'don’t', 'doesn’t', 'didn’t',
  'can’t', 'couldn’t', 'won’t', 'wouldn’t', 'shouldn’t', 'haven’t',
  'hasn’t', 'hadn’t', 'mustn’t', 'let’s',
};

/// Whether [word] is a function word that should not enter the review list.
///
/// Possessives are checked against their base (`reader's` is not a stopword,
/// but `it's` is): the tokenizer keeps the apostrophe, so `it's` arrives whole
/// and must not slip through because of the clitic.
bool isStopword(String word) {
  String w = word.toLowerCase().trim();
  if (w.isEmpty) return true;
  if (w.endsWith("'s") || w.endsWith('’s')) {
    w = w.substring(0, w.length - 2);
  }
  return kStopwords.contains(w);
}
