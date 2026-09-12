import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT.parents[1] / "watchos-aidlc-governance/inception/u01c-shared-boundary-manifest.json"
DECLARATION_TEMPLATE = r"\b(?:struct|enum|protocol|actor|class|typealias)\s+{name}\b"
EXECUTABLE_REFERENCE_TEMPLATE = r"\b{name}\b(?=\s*(?:<[^>]+>)?\s*(?:\.self|\(|\.|\?|\)|,|:))"


def swift_code(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    text = re.sub(r"//.*", " ", text)
    return "\n".join(re.sub(r'"(?:\\.|[^"\\])*"', lambda match: " " * len(match.group()), line) for line in text.splitlines())


class U01cManifestCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.entries = json.loads(MANIFEST.read_text())["entries"]

    def test_manifest_has_exactly_130_unique_rows(self):
        self.assertEqual(len(self.entries), 130)
        self.assertEqual(len({entry["type"] for entry in self.entries}), 130)

    def test_each_row_has_one_repository_declaration_in_manifested_owner(self):
        swift_files = [path for path in ROOT.rglob("*.swift") if "/.build/" not in str(path) and "/DerivedData" not in str(path)]
        failures = []
        for entry in self.entries:
            pattern = re.compile(DECLARATION_TEMPLATE.format(name=re.escape(entry["type"])))
            owners = [path.relative_to(ROOT).as_posix() for path in swift_files if pattern.search(swift_code(path.read_text()))]
            if owners != [entry["source"]]: failures.append({"type": entry["type"], "expected": entry["source"], "actual": owners})
        self.assertEqual(failures, [])

    def test_each_row_has_executable_typed_reference_in_assigned_test(self):
        failures = []
        for entry in self.entries:
            text = swift_code((ROOT / entry["test"]).read_text())
            pattern = re.compile(EXECUTABLE_REFERENCE_TEMPLATE.format(name=re.escape(entry["type"])))
            if not pattern.search(text): failures.append({"type": entry["type"], "test": entry["test"]})
        self.assertEqual(failures, [])

    def test_no_typealias_or_named_wrapper_shadows_any_manifest_type(self):
        names = "|".join(re.escape(entry["type"]) for entry in self.entries)
        forbidden = re.compile(rf"\btypealias\s+(?:{names})\b|\b(?:struct|enum|class|protocol)\s+(?:{names})(?:Wrapper|Adapter|Box|Alias)\b")
        failures = []
        for path in ROOT.rglob("*.swift"):
            if "/.build/" in str(path) or "/DerivedData" in str(path): continue
            for line_number, line in enumerate(path.read_text().splitlines(), 1):
                if forbidden.search(line): failures.append(f"{path.relative_to(ROOT)}:{line_number}:{line.strip()}")
        self.assertEqual(failures, [])


if __name__ == "__main__":
    unittest.main()
