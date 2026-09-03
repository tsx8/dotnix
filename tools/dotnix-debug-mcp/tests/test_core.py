import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from dotnix_debug_mcp import core


class ValidationTests(unittest.TestCase):
    def test_accepts_exact_unit_name(self):
        self.assertEqual(
            core.validate_unit("systemd-networkd.service"), "systemd-networkd.service"
        )

    def test_rejects_path_wildcard_and_bad_suffix(self):
        for value in (
            "../systemd.service",
            "systemd*.service",
            "systemd.service extra",
            "systemd",
            "",
            "x" * 129 + ".service",
        ):
            with self.assertRaises(core.InvalidInput):
                core.validate_unit(value)

    def test_rejects_invalid_limit_and_priority(self):
        with self.assertRaises(core.InvalidInput):
            core.validate_limit(0, 200, 80)
        with self.assertRaises(core.InvalidInput):
            core.validate_priority(8)


class RedactionTests(unittest.TestCase):
    def test_redacts_common_credential_forms(self):
        text, count = core.redact_text(
            "password=hunter2 Authorization: abc123 Bearer abc.def.ghi "
            "https://example.test/?token=secret"
        )
        self.assertEqual(count, 5)
        self.assertNotIn("hunter2", text)
        self.assertNotIn("abc.def.ghi", text)
        self.assertNotIn("secret", text)

    def test_redacts_private_key_block(self):
        text, count = core.redact_text(
            "-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----"
        )
        self.assertEqual(count, 1)
        self.assertNotIn("abc", text)


class JournalTests(unittest.TestCase):
    @staticmethod
    def entry(message: str, timestamp: int = 1_000_000_000_000_000) -> str:
        return json.dumps(
            {
                "__REALTIME_TIMESTAMP": str(timestamp),
                "PRIORITY": "3",
                "SYSLOG_IDENTIFIER": "test",
                "_PID": "123",
                "_SYSTEMD_UNIT": "test.service",
                "MESSAGE": message,
            }
        )

    def test_result_limits_and_redacts(self):
        result = core.journal_result(
            [self.entry("old password=one"), self.entry("new token=two")],
            "test.service",
            2,
        )
        self.assertEqual(result["returned"], 2)
        self.assertEqual(result["redactions"], 2)
        self.assertTrue(result["sensitive_hint"])
        self.assertEqual(result["entries"][-1]["message"], "new token=[REDACTED]")

    def test_budget_omits_older_entries(self):
        large = "x" * 2048
        result = core.journal_result(
            [self.entry(large, number) for number in range(100)],
            "test.service",
            100,
        )
        self.assertLess(result["returned"], 100)
        self.assertEqual(result["returned"], len(result["entries"]))
        self.assertGreater(result["omitted"], 0)

    def test_journal_uses_fixed_journalctl_arguments(self):
        commands = []

        def fake_run(command, timeout=10.0):
            commands.append(command)
            return subprocess.CompletedProcess(command, 0, "", "")

        original_run = core._run
        core._run = fake_run
        try:
            core.unit_journal("test.service", 20, 3)
        finally:
            core._run = original_run

        self.assertEqual(
            commands,
            [
                [
                    core.JOURNALCTL,
                    "--boot",
                    "--unit=test.service",
                    "--lines=20",
                    "--priority=3",
                    "--no-pager",
                    "--output=json",
                ]
            ],
        )


class GenerationTests(unittest.TestCase):
    def test_generations_from_read_only_profile_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            profile = root / "system"
            profile.symlink_to("system-2-link")
            (root / "system-2-link").symlink_to(
                "/nix/store/generation-2", target_is_directory=True
            )
            (root / "system-1-link").symlink_to(
                "/nix/store/generation-1", target_is_directory=True
            )
            original_profile = core.SYSTEM_PROFILE
            core.SYSTEM_PROFILE = profile
            try:
                result = core.nixos_generations(limit=2)
            finally:
                core.SYSTEM_PROFILE = original_profile

        self.assertEqual(result["current_generation"], 2)
        self.assertEqual(
            [item["generation"] for item in result["generations"]],
            [2, 1],
        )


if __name__ == "__main__":
    unittest.main()
