import contextlib
import io
import json
import unittest
from unittest.mock import MagicMock, patch

import collect_push_diagnostics as collector


class PushDiagnosticsTest(unittest.TestCase):
    def metrics(self):
        return "\n".join(
            'securechat_fcm_diagnostic_total{stage="' + stage + '",} 3.0'
            for stage in collector.STAGES
        )

    def test_only_closed_aggregate_labels_are_returned(self):
        text = self.metrics() + '\nother_metric{user="private"} 99\n'
        self.assertEqual({stage: 3.0 for stage in collector.STAGES}, collector.parse_counters(text))

    def test_old_artifact_or_extra_identity_labels_fail_closed(self):
        for text in ("", self.metrics().replace(',} 3.0', ',user="private"} 3.0')):
            with self.assertRaises(ValueError):
                collector.parse_counters(text)

    def test_loopback_only_no_redirects_and_no_error_body(self):
        connection = MagicMock()
        connection.getresponse.return_value.status = 302
        with patch.object(collector.http.client, "HTTPConnection", return_value=connection) as factory:
            with self.assertRaisesRegex(RuntimeError, "HTTP 302"):
                collector.fetch(8080, "/metrics", "test-token")
        factory.assert_called_once_with("127.0.0.1", 8080, timeout=10)
        connection.getresponse.return_value.read.assert_not_called()
        connection.close.assert_called_once()

    def test_report_contains_only_version_and_counters(self):
        token = "synthetic-metrics-credential-32-characters"
        version = json.dumps({"commit": "test", "builtAt": "test", "migrationTarget": "V21", "secret": token})
        output = io.StringIO()
        with patch.dict(collector.os.environ, {"METRICS_BEARER_TOKEN": token}, clear=True), \
             patch.object(collector, "fetch", side_effect=[version, self.metrics()]), \
             contextlib.redirect_stdout(output):
            self.assertEqual(0, collector.main())
        self.assertNotIn(token, output.getvalue())
        self.assertEqual({"build", "pushCounters"}, json.loads(output.getvalue()).keys())

    def test_exception_text_and_credentials_never_reach_output(self):
        secret = "synthetic-metrics-credential-32-characters"
        output = io.StringIO()
        with patch.object(collector, "read_token", side_effect=RuntimeError(secret)), \
             contextlib.redirect_stderr(output):
            self.assertEqual(1, collector.main())
        self.assertNotIn(secret, output.getvalue())


if __name__ == "__main__":
    unittest.main()
