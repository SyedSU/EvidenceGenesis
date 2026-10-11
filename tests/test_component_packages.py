import os
import tempfile
import unittest
import zipfile
from pathlib import Path
from scripts.component_packages import deterministic_zip, emit_candidates, inventory, sha256, source_commit, verify_full_package_parity


class ComponentPackagingTests(unittest.TestCase):
    def test_archives_preserve_exact_bytes_and_inventory(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'input';root.mkdir()
            (root / 'notice.txt').write_text('Unicode notes: ورکشاپ\n', encoding='utf-8')
            (root / 'docs').mkdir();(root / 'docs' / 'readme.txt').write_bytes(b'line one\r\nline two\r\n')
            output = Path(temp) / 'component.zip'
            facts = deterministic_zip(root, output)
            self.assertEqual(facts['size'], output.stat().st_size)
            self.assertEqual(facts['sha256'], sha256(output))
            self.assertEqual(facts['files'], inventory(root))
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(archive.read('notice.txt'), (root / 'notice.txt').read_bytes())
                self.assertEqual(archive.read('docs/readme.txt'), (root / 'docs/readme.txt').read_bytes())

    def test_timestamps_and_modes_do_not_change_archive(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'input';root.mkdir()
            file = root / 'notice.txt';file.write_bytes(b'Exact notice text\n')
            first = deterministic_zip(root, Path(temp) / 'first.zip')
            os.utime(file, (1600000000, 1700000000));file.chmod(0o600)
            second = deterministic_zip(root, Path(temp) / 'second.zip')
            self.assertEqual(first, second)

    def test_unknown_source_provenance_rejected(self):
        for value in [None, 'unknown', '', 'z' * 40, 'abc123']:
            with self.subTest(value=value), self.assertRaises(ValueError):source_commit(value)

    def test_empty_component_and_missing_required_payload_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with self.assertRaises(ValueError):deterministic_zip(root, root / 'empty.zip')
            provenance = {'gameSourceCommit': 'ed1daf0bf001b61586d9930840f2f1394092c079',
                          'runtime': {'sourceCommit': 'd81235049384534c167caea52b85a694f6103d14'},
                          'model': {'sourceCommit': 'ed1daf0bf001b61586d9930840f2f1394092c079'}}
            with self.assertRaisesRegex(ValueError, 'Required component file'):
                emit_candidates({kind: root for kind in ['game', 'runtime', 'model']}, root / 'output', provenance)
            self.assertFalse((root / 'output' / 'genesis-candidate-report.json').exists())

    def test_full_package_parity_detects_changed_payload(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'input';root.mkdir()
            (root / 'notice.txt').write_bytes(b'Exact source notice')
            facts = deterministic_zip(root, Path(temp) / 'component.zip')
            full = Path(temp) / 'full.zip'
            for contents, fails in [(b'Exact source notice', False), (b'Different contents', True)]:
                with zipfile.ZipFile(full, 'w') as archive:
                    archive.writestr('EvidenceGenesis/notice.txt', contents)
                    archive.writestr('EvidenceGenesis/SHA256SUMS.json', '{}')
                packages = [{'kind': 'game', **facts}]
                if fails:
                    with self.assertRaisesRegex(ValueError, 'byte parity'):verify_full_package_parity(full, packages, {'licenses': []})
                else:verify_full_package_parity(full, packages, {'licenses': []})

    def test_symlinks_cannot_escape_component(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'input';root.mkdir()
            outside = Path(temp) / 'outside.txt';outside.write_text('outside')
            try:(root / 'link.txt').symlink_to(outside)
            except OSError:self.skipTest('Platform cannot create symlinks')
            with self.assertRaises(ValueError):inventory(root)


if __name__ == '__main__':unittest.main()
