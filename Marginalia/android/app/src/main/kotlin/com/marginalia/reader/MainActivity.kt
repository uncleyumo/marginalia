package com.marginalia.reader

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity, not FlutterActivity. It is a FlutterActivity that also
// implements the MediaBrowserService's client callback, which is what lets a tap
// on the media notification bring the reader back to the app instead of opening
// a blank task. With a plain FlutterActivity the notification still appears and
// the transport still works — tapping it just does nothing, which is the kind of
// half-working that is worse than absent.
class MainActivity : AudioServiceActivity()
