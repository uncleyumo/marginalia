import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// A back label that is actually a button.
///
/// Every screen had one of these as plain `Text`, which is worse than not
/// having it: it names a destination and then does nothing when touched, so a
/// reader presses it, nothing happens, and they reach for the system Back
/// instead — which is how an app teaches people to leave.
class BackLabel extends StatelessWidget {
  const BackLabel({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: TypeScale.sans,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.ink2,
            ),
          ),
        ),
      ),
    );
  }
}
