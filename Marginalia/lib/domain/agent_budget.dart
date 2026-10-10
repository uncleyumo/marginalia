// The hard limits on a writing run. Pure constants, no imports, so they can be
// asserted by `tool/check_agent.dart` without a widget binding.
//
// These exist because the writing agent can make SEVERAL paid calls, and an
// unbounded loop that spends money is the one failure this app cannot have.
// Every number here is checked BEFORE the blocking work it bounds, and the
// three counters (calls, tool calls, turns) only ever increase — which is the
// whole proof that the loop terminates.

/// Model round trips before the run stops researching and writes.
///
/// Three: the reader's stated flow is "read one story, then ask for another,
/// then write" — two browsing turns and one writing turn. A fourth would only
/// ever be slack.
const int kMaxTurns = 3;

/// Tool calls in total, across all turns.
///
/// Separate from [kMaxTurns] because one turn can ask for several tools at
/// once: the turn cap alone would let a single turn fire ten searches. Two
/// stories plus one search is the shape being allowed for.
const int kMaxToolCalls = 3;

/// The hard ceiling on PAID HTTP POSTs, and the number the cost line states.
///
/// Three turns, plus one forced finish, plus one retry anywhere. Retries are
/// counted against this rather than given their own allowance: a retry is a
/// second paid call, and a separate budget would double the advertised
/// worst-case price of an action whose whole promise is that it is affordable.
const int kMaxModelCalls = 5;

/// Attempts for ONE logical call: the original plus two retries.
const int kMaxAttemptsPerCall = 3;

/// Consecutive tool failures before the run gives up researching.
///
/// One failure is bad luck. Two in a row means the tool is down, and asking a
/// third time spends a paid call to learn nothing.
const int kMaxConsecutiveToolFailures = 2;

/// How many times the identical call (same tool, same arguments) is tolerated.
///
/// The second is served from a signature cache without touching the network.
/// The third is refused and forces the run to write with what it has — this is
/// what kills the classic "call the same tool forever" loop.
const int kMaxRepeatedIdenticalToolCall = 2;

/// Wall clock for the whole run, in seconds.
///
/// THESE NUMBERS ARE MEASURED, NOT GUESSED, and the first version of them was
/// wrong in a way that made the whole feature fail.
///
/// They were 120 and 60, on the assumption that a model call takes 10–20 s.
/// Then a real write was run against MiMo and the FIRST call timed out twice in
/// a row: 60 s, then 52 s, and the run gave up having spent two requests and
/// written nothing. The cause was not the model hanging — it was the model
/// WORKING. Timing the same request directly:
///
///   · a bare "say hello"                              1.1 s
///   · the same, with one tool offered                 2.5 s
///   · the full prompt, 30 headlines, two tools        8.9 s
///   · a real 180-word article with Chinese beside it 72.4 s
///
/// Writing is the slow part, by an order of magnitude, and it is the part this
/// app is for. A 500-word article is roughly three times that again, so a
/// ceiling has to be generous enough to never cut off a legitimate article —
/// a timeout that fires on a working call is worse than a slow one, because it
/// charges the reader and gives them nothing.
///
/// MEASURED AGAIN AFTER THE FIRST VALUE TURNED OUT TO BE TIGHT.
///
/// The 240/420 pair was chosen from a 72 s article. Then a real research run
/// was timed end to end and the second turn — the one that writes after reading
/// two stories — took **230 seconds**: 10911 completion tokens, of which 31441
/// characters were the model's own reasoning. The whole run was 274 s. The
/// per-call ceiling of 240 s cleared that call by ten seconds, which is not a
/// margin, it is a coin toss.
///
/// 600 s is a run long enough for a slow research turn plus a slow writing
/// turn plus a retry. Ten minutes of "Writing…" is a long wait, and it is the
/// honest one: the alternative is a timeout that fires on a call that was going
/// to succeed, which charges the reader and hands them nothing.
const int kMaxWallClockSeconds = 600;

/// Per-call timeout, in seconds. Clamped at call time to
/// `min(this, remaining - kMinCallWindowSeconds)` so a single call can never
/// outlive the run.
///
/// 360 against the 230 s measured writing turn: the same call on a longer
/// article, or on a day the model thinks harder, still finishes.
const int kPerCallTimeoutSeconds = 360;

/// A call that cannot finish in this many seconds is not worth starting.
const int kMinCallWindowSeconds = 8;

/// Total time spent in backoff sleeps, in milliseconds.
///
/// Backoff counts against the wall clock like everything else, so it needs its
/// own ceiling or retries could eat the entire run.
const int kMaxBackoffTotalMs = 5000;

/// Timeout for one tool call, in seconds. The measured worst case is ~1.1 s
/// (the web search); 8 s is generous without being a hang.
const int kToolTimeoutSeconds = 8;

/// Characters of a fetched story fed back to the model.
///
/// The real body is ~1.9 KB of HTML and ~640 characters once stripped, so this
/// is generous. It is a ceiling, not a target: it exists so one pathological
/// page cannot blow up the prompt.
const int kMaxStoryChars = 4000;

/// Characters kept from each web-search snippet.
///
/// Measured: `count: 3` returns 2,820 characters of raw envelope, most of it
/// `hostlogo` URLs and a `request_id`. Reduced to `{title, snippet, url}` with
/// snippets cut here, the same result is ~1,200 characters — a third of the
/// prompt cost for the same information.
const int kMaxSnippetChars = 400;

/// Results asked of the web search by default, and the range it is clamped to.
///
/// Five results is 5,773 characters of envelope — too much to put in a prompt
/// that also carries a plan and a story. Three is the useful middle.
const int kSearchCountDefault = 3;
const int kSearchCountMin = 1;
const int kSearchCountMax = 5;

/// Lines kept in the in-memory debug log.
const int kLogRingSize = 300;

/// Characters of a response body kept for the log, after scrubbing.
const int kLogBodySnippetChars = 300;
