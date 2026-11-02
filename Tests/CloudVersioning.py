"""Check the release versions written by the actual Xcode Cloud lifecycle hook."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HOOK = Path(__file__).resolve().parent.parent / "ci_scripts/ci_pre_xcodebuild.sh"
INITIAL = "MARKETING_VERSION = 0.2.1\nCURRENT_PROJECT_VERSION = 6\n"


class CloudVersioningChecks(unittest.TestCase):
    def run_hook(self, tag=None, build="42", checkout=True):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            version_file = root / "Configuration/Version.xcconfig"
            if checkout:
                version_file.parent.mkdir()
                version_file.write_text(INITIAL)
                (root / "RocketUp.xcodeproj").mkdir()
            environment = os.environ.copy()
            environment.pop("CI_TAG", None)
            environment["CI_PRIMARY_REPOSITORY_PATH"] = directory
            environment["CI_BUILD_NUMBER"] = build
            if tag is not None:
                environment["CI_TAG"] = tag
            result = subprocess.run(["/bin/bash", str(HOOK)], env=environment, capture_output=True, text=True)
            return result, version_file.read_text() if version_file.exists() else None

    def test_branch_keeps_marketing_version_and_uses_cloud_build_number(self):
        result, config = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(config, "MARKETING_VERSION = 0.2.1\nCURRENT_PROJECT_VERSION = 42\n")

    def test_release_tags_set_the_marketing_version(self):
        for tag in ["1.2.3", "v1.2.3"]:
            with self.subTest(tag=tag):
                result, config = self.run_hook(tag)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(config, "MARKETING_VERSION = 1.2.3\nCURRENT_PROJECT_VERSION = 42\n")

    def test_invalid_release_tags_leave_versions_unchanged(self):
        for tag in ["v", "1.2", "release-candidate"]:
            with self.subTest(tag=tag):
                result, config = self.run_hook(tag)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(config, INITIAL)

    def test_invalid_build_number_leaves_versions_unchanged(self):
        for build in ["", "0", "not-a-number"]:
            with self.subTest(build=build):
                result, config = self.run_hook(build=build)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(config, INITIAL)

    def test_target_settings_do_not_override_cloud_versions(self):
        project = HOOK.parent.parent / "RocketUp.xcodeproj/project.pbxproj"
        import json
        result = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(project)],
                                capture_output=True, text=True, check=True)
        objects = json.loads(result.stdout)["objects"]
        target = next(obj for obj in objects.values()
                      if obj.get("isa") == "PBXNativeTarget" and obj.get("name") == "RocketUp")
        configs = objects[target["buildConfigurationList"]]["buildConfigurations"]
        for config in configs:
            settings = objects[config]["buildSettings"]
            self.assertNotIn("MARKETING_VERSION", settings)
            self.assertNotIn("CURRENT_PROJECT_VERSION", settings)

    def test_artifact_reuse_does_not_require_a_source_checkout(self):
        result, config = self.run_hook(checkout=False, build="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(config)


if __name__ == "__main__":
    unittest.main()
