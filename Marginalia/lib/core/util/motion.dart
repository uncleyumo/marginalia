// Motion, with the accessibility switch honoured in one place.
//
// The design system promises that `prefers-reduced-motion` is respected
// globally. Flutter exposes the reader's choice through
// `MediaQuery.disableAnimationsOf`, and the only way that promise survives is
// for every animation to ask this helper rather than hard-code a duration.

import 'package:flutter/widgets.dart';

/// [duration], or zero when the reader asked the platform for less motion.
Duration motionDuration(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

/// Whether transitions should be skipped entirely.
bool reducedMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);
