#!/usr/bin/env python3
"""Bounded retry for transient Gradle artifact downloads, not compile/sign errors.

Called only by GitHub Actions after pub get/analyze/test. No command or API
keys are printed. Reuses the Gradle cache; never clean/refresh on retry.
"""
import collections
import os
import random
import re
import subprocess
import sys
import time

MAX_ATTEMPTS = 3
BACKOFF_SECONDS = (60, 180)


def transient_download_failure(output):
    text = output.lower()
    download = any(marker in text for marker in (
        'could not resolve', 'could not get resource', 'could not download',
        'gradle threw an error while downloading artifacts',
    ))
    if not download:
        return False
    return bool(re.search(r'(?:status code|response code|http(?:/\d(?:\.\d)?)?)\s*[:=]?\s*(429|502|503|504)\b', text)) or any(marker in text for marker in (
        'read timed out', 'connect timed out', 'connection reset',
        'temporary failure in name resolution',
    ))


def stream_build(command, env):
    tail = collections.deque(maxlen=4000)
    with subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True,
                          encoding='utf-8', errors='replace', bufsize=1) as process:
        for line in process.stdout:
            print(line, end='', flush=True)
            tail.append(line[-8192:])
        return process.wait(), ''.join(tail)


def build(target, env=None, run=stream_build, sleep=time.sleep, jitter=None):
    if target not in ('apk', 'appbundle'):
        raise ValueError('Target must be apk or appbundle')
    child_env = dict(os.environ if env is None else env)
    # Limit simultaneous dependency requests. These do not change app code,
    # Kotlin/Gradle versions, signing or the resulting build target.
    child_env['GRADLE_OPTS'] = (child_env.get('GRADLE_OPTS', '') +
                               ' -Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false').strip()
    command = ['flutter', 'build', target, '--release', '--no-pub',
               '--dart-define=TMDB_API_KEY=' + child_env.get('TMDB_API_KEY', ''),
               '--dart-define=OPENROUTER_API_KEY=' + child_env.get('OPENROUTER_API_KEY', '')]
    for attempt in range(1, MAX_ATTEMPTS + 1):
        print(f'Android {target}: build attempt {attempt}/{MAX_ATTEMPTS}', flush=True)
        code, tail = run(command, child_env)
        if code == 0:
            return 0
        if attempt == MAX_ATTEMPTS or not transient_download_failure(tail):
            print('::error::Android build failed. No more retries; inspect the build output.', flush=True)
            return code if code > 0 else 128 - code
        delay = BACKOFF_SECONDS[attempt - 1] + (random.randint(0, 20) if jitter is None else jitter)
        print(f'::warning::Transient dependency-download failure; waiting {delay}s before retry. Cached downloads retained.', flush=True)
        sleep(delay)
    return 1


if __name__ == '__main__':
    if len(sys.argv) != 2 or sys.argv[1] not in ('apk', 'appbundle'):
        raise SystemExit('Usage: build_android_ci.py apk|appbundle')
    raise SystemExit(build(sys.argv[1]))
