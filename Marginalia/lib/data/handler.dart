// The transport that lives outside the app.
//
// DESIGN's use case #2 is a commuter with the phone in a pocket: screen off,
// phone in a bag, article still being read aloud. Without a foreground service
// Android suspends the process the moment the screen goes off, so the promise
// "listen on the way to work" was one this app could not keep — the player
// stopped the instant the reader stopped looking at it.
//
// This is the piece that keeps it. It is deliberately thin.
//
// The handler owns NO playback state of its own. The Listen screen owns the
// index, whether it is playing, and which sentence is current; it pushes what is
// true into [publish] and the handler forwards it to the notification and the
// lock screen. A handler that tracked position as well would be a second copy of
// the truth, and the two would disagree the first time a sentence was skipped
// from the lock screen — which is precisely the "second copy" DESIGN forbids.

import 'package:audio_service/audio_service.dart';

/// The lock screen, the media notification, and the headset buttons.
class MarginaliaAudioHandler extends BaseAudioHandler {
  MarginaliaAudioHandler();

  /// Who is listening for a transport tap right now.
  ///
  /// Set when the Listen screen appears and cleared when it goes away, so a
  /// lock-screen button can never call into a State that has been disposed. The
  /// previous arrangement — a screen that outlived its own route — is what
  /// produced the red screen a screenshot caught.
  void Function()? onPlay;
  void Function()? onPause;
  void Function()? onNext;
  void Function()? onPrevious;

  @override
  Future<void> play() async => onPlay?.call();

  @override
  Future<void> pause() async => onPause?.call();

  @override
  Future<void> skipToNext() async => onNext?.call();

  @override
  Future<void> skipToPrevious() async => onPrevious?.call();

  @override
  Future<void> stop() async {
    detach();
    _idle();
    await super.stop();
  }

  /// Forget every callback. Called when the Listen screen leaves, and on stop.
  void detach() {
    onPlay = null;
    onPause = null;
    onNext = null;
    onPrevious = null;
  }

  /// State the truth about what is being heard.
  ///
  /// [sentence] is the artist line because on a lock screen the thing being read
  /// is the only line that changes, and the article title alone would leave the
  /// reader unable to tell whether playback had moved on.
  void publish({
    required String articleTitle,
    required String sentence,
    required int index,
    required int total,
    required bool playing,
  }) {
    mediaItem.add(
      MediaItem(
        id: 'marginalia:sentence:$index',
        title: articleTitle,
        artist: sentence,
        album: 'Marginalia',
        // A sentence has no duration until the engine has spoken it. A made-up
        // number would put a progress bar on the lock screen that lies, and
        // DESIGN is explicit that this app shows no progress it cannot honour.
        duration: null,
      ),
    );

    playbackState.add(
      playbackState.value.copyWith(
        controls: <MediaControl>[
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const <int>[0, 1, 2],
        // No seek bar: there is no position to seek to. The transport is
        // previous / play / next and nothing else, on screen and off it alike.
        systemActions: const <MediaAction>{},
        processingState: AudioProcessingState.ready,
        playing: playing,
        updatePosition: Duration.zero,
        queueIndex: index,
      ),
    );
  }

  void _idle() {
    playbackState.add(
      playbackState.value.copyWith(
        controls: const <MediaControl>[],
        androidCompactActionIndices: const <int>[],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        queueIndex: null,
      ),
    );
  }
}
