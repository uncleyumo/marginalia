// Bump the build number before every delivery.
//
// Settings shows `version X.Y.Z (N)` read from the ANDROID PACKAGE MANAGER —
// what is actually installed on the phone, not what the source tree says. That
// is the one situation the line exists for: standing over the phone asking "is
// this the APK I just made?". It stops answering that question the moment two
// different builds carry the same number, which is exactly what happens when
// somebody forgets to edit `pubspec.yaml` by hand.
//
// So the edit is a script. One command, no judgement required:
//
//   dart tool/bump_version.dart
//
// It moves `versionName`'s build number only (`+11` → `+12`), never the
// semantic part. A build that fixes a bug is not a new API.

import 'dart:io';

import 'package:path/path.dart' as p;

/// `version: 0.4.0+11` — the whole line, wherever the spaces fall.
final RegExp _versionLine = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+(\d+)\s*$',
    multiLine: true);

void main(List<String> args) {
  final Directory here = Directory.current;
  final File pubspec = File(p.join(here.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    stderr.writeln('no pubspec.yaml in ${here.path} — run this from the '
        'Marginalia directory');
    exit(1);
  }

  final String before = pubspec.readAsStringSync();
  final RegExpMatch? m = _versionLine.firstMatch(before);
  if (m == null) {
    stderr.writeln('could not find a `version: X.Y.Z+N` line in pubspec.yaml');
    exit(1);
  }

  final String name = m.group(1)!;
  final int build = int.parse(m.group(2)!) + 1;
  final String after = before.replaceRange(m.start, m.end, 'version: $name+$build');

  // Write only when something actually moved, so a second run in a row is
  // visible rather than silently rewriting the same bytes.
  if (after == before) {
    stderr.writeln('nothing changed — the build number did not parse');
    exit(1);
  }
  pubspec.writeAsStringSync(after);

  // `android/local.properties` is Flutter's own cache of the same two numbers.
  // It is rewritten on every build, so it is not the source of truth — but a
  // stale one makes `flutter run` report the old version until the next build
  // has finished, which is exactly the window somebody checks in.
  final File localProps = File(p.join(here.path, 'android', 'local.properties'));
  if (localProps.existsSync()) {
    final String props = localProps.readAsStringSync();
    final String patched = props
        .replaceAll(RegExp(r'^flutter\.versionName=.*$', multiLine: true),
            'flutter.versionName=$name')
        .replaceAll(RegExp(r'^flutter\.versionCode=.*$', multiLine: true),
            'flutter.versionCode=$build');
    if (patched != props) localProps.writeAsStringSync(patched);
  }

  // Only `--quiet` silences this. The whole point of the script is that the
  // number is now on screen in the build log, where a human can see it landed.
  if (!args.contains('--quiet')) {
    stdout.writeln('$name+$build  (was $name+${build - 1})');
  }
}
