"""Run a flutter subcommand with its output going to a FILE, never a pipe.

Why this exists: the Dart VM cannot create a piped child process in this
environment. It fails with

    CreateFile failed 231 (All pipe instances are busy)
    (at ../../runtime/bin/process_win.cc:742)

and flutter_tools dies on its very first `git log` / `cmd /c ver`. That is not a
project problem — Python spawns subprocesses here without complaint.

The remaining trick is that flutter_tools ALSO creates pipes for its own
children, so handing IT a file rather than a pipe is what makes the difference:
nothing in the chain ever asks for an anonymous pipe.

Usage:
    python tool/flutter_run.py build apk --debug
    python tool/flutter_run.py run -d emulator-5554
"""
import os
import subprocess
import sys

SDK = r'E:\Dev_work\Android_Dev\Dev_Tools\Flutter_SDK\flutter_windows_3.44.3-stable\bin\flutter.bat'
PROJECT = r'E:\Dev_work\Flutter_Dev\marginalia\Marginalia'
LOG = os.path.join(PROJECT, 'build', 'flutter_run.log')

env = dict(os.environ)
env['PUB_HOSTED_URL'] = 'https://pub.flutter-io.cn'
env['FLUTTER_STORAGE_BASE_URL'] = 'https://storage.flutter-io.cn'
env['ANDROID_HOME'] = r'E:\Dev_work\Android_Dev\Dev_Tools\Android_SDK\SDK_For_AS352'
env['ANDROID_SDK_ROOT'] = env['ANDROID_HOME']
env['JAVA_HOME'] = r'E:\Dev_work\Java_Dev\JDK_SRC\JDK_21_GRAALVM'
env['PATH'] = env['ANDROID_HOME'] + os.pathsep + env['JAVA_HOME'] + os.pathsep + env['PATH']

# CI mode makes the tools quieter and, more importantly, keeps it from trying to
# phone home for version checks — which is another subprocess.
env['FLUTTER_SUPPRESS_ANALYTICS'] = 'true'
env['BOT'] = 'true'

args = sys.argv[1:]
os.makedirs(os.path.dirname(LOG), exist_ok=True)
print('running: flutter ' + ' '.join(args))
print('log: ' + LOG, flush=True)

# DETACHED_PROCESS + a real file for each stream: no pipe is created anywhere in
# this chain, which is the whole point.
flags = getattr(subprocess, 'DETACHED_PROCESS', 0x00000008) | getattr(
    subprocess, 'CREATE_NEW_PROCESS_GROUP', 0x00000200)
with open(LOG, 'wb') as out:
    proc = subprocess.Popen(
        [SDK] + args,
        cwd=PROJECT,
        env=env,
        stdout=out,
        stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL,
        creationflags=flags,
    )
    code = proc.wait()

print('--- exit %d ---' % code)
try:
    with open(LOG, 'r', encoding='utf-8', errors='replace') as fh:
        text = fh.read()
except OSError as e:
    text = 'could not read the log: %s' % e
print(text[-16000:])
sys.exit(code)