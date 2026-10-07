// Static analysis driver, because `flutter analyze` cannot run in this
// environment.
//
// The problem: flutter_tools shells out to `where.exe` and `git`, and Dart
// cannot create a piped child process here (CreateFile failed 231). The
// analyzer is a pure-Dart library, so this runs the same analysis the IDE runs.
//
// Note the invocation: `dart tool/analyze.dart`, NOT `dart run tool/analyze.dart`.
// The latter goes through dartdev, which triggers native-asset build hooks, and
// those spawn `dart compile kernel` as a child process — which is exactly what
// fails. Plain `dart <file>` skips that.
//
// analyzer 10 renamed the error model: `AnalysisError`/`ErrorType` are gone,
// replaced by `Diagnostic` and a `DiagnosticSeverity` class with static
// constants (not an enum). This file is written against the current API.
//
// Not shipped in the app: a development tool, kept out of lib/.
//   dart tool/analyze.dart [project-root]

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';

Future<void> main(List<String> args) async {
  // The analyzer insists on an absolute, NORMALISED path: no `.` segment and no
  // trailing separator. `Directory('.').absolute` violates both, so build the
  // string and trim it by hand.
  String raw = args.isEmpty ? '.' : args.first;
  final Directory abs = Directory(raw).absolute;
  String path = abs.path;
  // collapse a trailing `/.` and then any trailing separator
  if (path.endsWith('${Platform.pathSeparator}.')) {
    path = path.substring(0, path.length - 2);
  }
  while (path.length > 3 && path.endsWith(Platform.pathSeparator)) {
    path = path.substring(0, path.length - 1);
  }
  final Directory root = Directory(path);
  final Stopwatch sw = Stopwatch()..start();

  // Collect files first: the context root alone does not enumerate them, and an
  // empty scan would report success while checking nothing.
  final List<String> targets = <String>[];
  for (final String dir in <String>['lib', 'test', 'tool']) {
    final Directory d = Directory('${root.path}${Platform.pathSeparator}$dir');
    if (!d.existsSync()) continue;
    for (final FileSystemEntity e in d.listSync(recursive: true)) {
      if (e is File && e.path.endsWith('.dart')) targets.add(e.absolute.path);
    }
  }
  if (targets.isEmpty) {
    stdout.writeln('no .dart files under lib/ test/ tool/ — nothing to check');
    exit(2);
  }

  final AnalysisContextCollection collection =
      AnalysisContextCollection(includedPaths: <String>[root.path]);

  int errors = 0, warnings = 0, infos = 0;
  final List<String> lines = <String>[];

  for (final String path in targets) {
    final AnalysisContext ctx = collection.contextFor(path);
    // The explicit cast is required, not redundant: this analyzer version does
    // not promote SomeErrorsResult to AnalysisResultWithDiagnostics after the
    // `continue`, so the `is` test alone leaves the static type unchanged.
    final Object r = await ctx.currentSession.getErrors(path);
    if (r is! AnalysisResultWithDiagnostics) continue;
    // ignore: unnecessary_cast — required: this analyzer version does not
    // promote SomeErrorsResult across the `continue` above.
    final List<Diagnostic> diags =
        (r as AnalysisResultWithDiagnostics).diagnostics;
    final String source = File(path).readAsStringSync();
    for (final Diagnostic d in diags) {
      // Diagnostic.severity returns the legacy `Severity` (error/warning/info);
      // diagnosticCode.severity returns DiagnosticSeverity. The former is the
      // one this package actually re-exports.
      final String sevName = _sev(d.severity);
      if (sevName == 'ERROR') {
        errors++;
      } else if (sevName == 'WARNING') {
        warnings++;
      } else {
        infos++;
      }
      lines.add('${sevName.padRight(7)} ${_rel(root, path)}:'
          '${_lineOf(d, source)}  ${d.diagnosticCode.name}  ${d.message}');
    }
  }

  sw.stop();
  lines.sort();
  for (final String l in lines) {
    stdout.writeln(l);
  }
  stdout.writeln('');
  stdout.writeln('${targets.length} files · ${sw.elapsedMilliseconds}ms · '
      'errors=$errors warnings=$warnings infos=$infos');
  exit(errors > 0 ? 1 : 0);
}

String _rel(Directory root, String path) =>
    path.replaceFirst('${root.path}${Platform.pathSeparator}', '');

/// 1-based line number for an offset, by counting newlines in the source.
///
/// The analyzer reports a character offset; on a 300-line file that is close to
/// useless, and this tool exists precisely because the real `dart analyze`
/// cannot run here.
int _lineOf(Diagnostic d, String source) {
  final int off = d.offset;
  if (off <= 0) return 1;
  int line = 1;
  final int limit = off < source.length ? off : source.length;
  for (int i = 0; i < limit; i++) {
    if (source.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

String _sev(Severity s) {
  if (s == Severity.error) return 'ERROR';
  if (s == Severity.warning) return 'WARNING';
  if (s == Severity.info) return 'INFO';
  return 'HINT';
}
