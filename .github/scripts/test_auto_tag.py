import subprocess
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

import auto_tag


class AutoTagTest(unittest.TestCase):
    def setUp(self):
        self.pubspec = patch.object(auto_tag.Path, "read_text", return_value="version: 1.2.3\n").start()
        self.run = patch.object(auto_tag.subprocess, "run").start()
        self.run.return_value.returncode = 1
        self.output = patch.object(auto_tag.subprocess, "check_output").start()
        self.request = patch.object(auto_tag, "urlopen").start()
        self.request.side_effect = HTTPError("https://pub.dev", 404, "Not found", {}, None)
        self.addCleanup(patch.stopall)

    def commands(self):
        return [call.args[0] for call in self.run.call_args_list]

    def test_unpublished_version_is_validated_before_tagging_and_pushing(self):
        auto_tag.main()
        self.assertEqual(self.commands(), [
            ["git", "merge-base", "--is-ancestor", "HEAD", "origin/main"],
            ["flutter", "pub", "publish", "--dry-run"],
            ["git", "show-ref", "--verify", "--quiet", "refs/tags/requests_inspector_plus-v1.2.3"],
            ["git", "tag", "requests_inspector_plus-v1.2.3"],
            ["git", "push", "origin", "refs/tags/requests_inspector_plus-v1.2.3"],
        ])

    def test_already_published_version_is_skipped(self):
        self.request.side_effect = None
        auto_tag.main()
        self.assertEqual(len(self.commands()), 1)

    def test_prerelease_with_build_metadata_is_preserved(self):
        self.pubspec.return_value = "version: 1.2.3-beta.1+2\n"
        auto_tag.main()
        self.request.assert_called_once_with(
            "https://pub.dev/api/packages/requests_inspector_plus/versions/1.2.3-beta.1%2B2",
            timeout=30,
        )
        self.assertEqual(self.commands()[-1], [
            "git", "push", "origin", "refs/tags/requests_inspector_plus-v1.2.3-beta.1+2"
        ])

    def test_pub_dev_outage_does_not_create_a_release(self):
        self.request.side_effect = HTTPError("https://pub.dev", 503, "Unavailable", {}, None)
        with self.assertRaises(HTTPError):
            auto_tag.main()
        self.assertEqual(len(self.commands()), 1)

    def test_failed_validation_does_not_tag(self):
        self.run.side_effect = [None, subprocess.CalledProcessError(1, "flutter")]
        with self.assertRaises(subprocess.CalledProcessError):
            auto_tag.main()
        self.assertEqual(len(self.commands()), 2)

    def test_commit_outside_main_is_rejected(self):
        self.run.side_effect = subprocess.CalledProcessError(1, "git")
        with self.assertRaises(subprocess.CalledProcessError):
            auto_tag.main()
        self.request.assert_not_called()

    def test_existing_tag_cannot_be_moved(self):
        self.run.return_value.returncode = 0
        self.output.side_effect = ["old-commit\n", "new-commit\n"]
        with self.assertRaises(RuntimeError):
            auto_tag.main()
        self.assertEqual(len(self.commands()), 3)

    def test_retry_does_not_push_an_existing_tag(self):
        self.run.return_value.returncode = 0
        self.output.side_effect = ["same-commit\n", "same-commit\n"]
        auto_tag.main()
        self.assertEqual(len(self.commands()), 3)

    def test_invalid_version_is_rejected(self):
        self.pubspec.return_value = "version: not-a-version\n"
        with self.assertRaises(ValueError):
            auto_tag.main()
        self.request.assert_not_called()


if __name__ == "__main__":
    unittest.main()
