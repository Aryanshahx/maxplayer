import contextlib
import io
import unittest
from build_android_ci import build, transient_download_failure

RATE_LIMIT = '''Could not resolve org.jetbrains.kotlin:kotlin-gradle-plugin-api:2.2.0.
Could not GET 'https://repo.maven.apache.org/maven2/test.pom'. Received status code 429 from server: Too Many Requests'''


class DownloadRetryTests(unittest.TestCase):
    def invoke(self, results, target='apk'):
        calls, waits = [], []
        def run(command, env):
            calls.append((list(command), dict(env)))
            return results[len(calls)-1]
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = build(target, env={'TMDB_API_KEY': 'private-tmdb', 'OPENROUTER_API_KEY': 'private-ai', 'GRADLE_OPTS': '-Xmx2g'}, run=run, sleep=waits.append, jitter=0)
        self.assertNotIn('private-tmdb', output.getvalue())
        self.assertNotIn('private-ai', output.getvalue())
        return code, calls, waits

    def test_rate_limit_then_success(self):
        code, calls, waits = self.invoke([(1, RATE_LIMIT), (0, 'done')])
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 2)
        self.assertEqual(waits, [60])
        self.assertIn('-Dorg.gradle.workers.max=2', calls[0][1]['GRADLE_OPTS'])
        self.assertIn('-Xmx2g', calls[0][1]['GRADLE_OPTS'])

    def test_max_three_attempts_and_failure_stays_failure(self):
        code, calls, waits = self.invoke([(1, RATE_LIMIT)]*3, 'appbundle')
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 3)
        self.assertEqual(waits, [60, 180])
        self.assertEqual(calls[0][0][:3], ['flutter', 'build', 'appbundle'])

    def test_compile_error_is_not_retried(self):
        code, calls, waits = self.invoke([(1, 'Error: Undefined name x; Compilation failed')])
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)
        self.assertEqual(waits, [])

    def test_signing_error_is_not_retried(self):
        code, calls, waits = self.invoke([(1, 'Keystore was tampered with, or password was incorrect')])
        self.assertEqual(code, 1)
        self.assertEqual(len(calls), 1)
        self.assertEqual(waits, [])

    def test_success_does_not_retry(self):
        code, calls, waits = self.invoke([(0, '')])
        self.assertEqual((code, len(calls), waits), (0, 1, []))
        self.assertNotIn('clean', calls[0][0])
        self.assertNotIn('--refresh-dependencies', calls[0][0])
        self.assertIn('--no-pub', calls[0][0])

    def test_non_download_429_is_not_a_retry_reason(self):
        self.assertFalse(transient_download_failure('Version code 429; Dart compilation failed'))
        self.assertFalse(transient_download_failure('HTTP 429 from an application API test'))
        self.assertFalse(transient_download_failure('Could not resolve an undefined Dart variable'))

    def test_temporary_gateway_and_timeout_errors(self):
        for code in (502, 503, 504):
            self.assertTrue(transient_download_failure(f'Could not download artifact: Received status code {code}'))
        self.assertTrue(transient_download_failure('Could not get resource; Read timed out'))
        self.assertFalse(transient_download_failure('Could not download: Received status code 404'))
        self.assertFalse(transient_download_failure('Could not get resource: PKIX certificate validation failed'))

    def test_invalid_target_rejected(self):
        with self.assertRaises(ValueError):
            self.invoke([], 'windows')


if __name__ == '__main__':
    unittest.main()
