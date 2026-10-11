"""Deterministic, unsigned component candidates; publication URLs are never inferred."""
import hashlib
import json
import re
import zipfile
from pathlib import Path

VERSION = '0.4.0'


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def inventory(root):
    result = []
    for path in sorted(Path(root).rglob('*')):
        if path.is_symlink():
            raise ValueError('Component symlinks are not permitted')
        if path.is_file():
            result.append({'path': path.relative_to(root).as_posix(),
                           'size': path.stat().st_size, 'sha256': sha256(path)})
    if not result:
        raise ValueError('Empty component')
    return result


def deterministic_zip(root, destination):
    """Same input bytes produce the same ZIP, independent of file timestamps/modes."""
    root, destination = Path(root), Path(destination)
    files = inventory(root)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for entry in files:
            info = zipfile.ZipInfo(entry['path'], date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            with (root / entry['path']).open('rb') as source, archive.open(info, 'w', force_zip64=True) as output:
                for chunk in iter(lambda: source.read(1024 * 1024), b''):
                    output.write(chunk)
    # Compare every archived byte with the source inventory, not just ZIP CRCs.
    with zipfile.ZipFile(destination) as archive:
        if archive.namelist() != [entry['path'] for entry in files]:
            raise ValueError('Unexpected ZIP inventory')
        for entry in files:
            with archive.open(entry['path']) as stream:
                actual = hashlib.file_digest(stream, 'sha256').hexdigest()
            if archive.getinfo(entry['path']).file_size != entry['size'] or actual != entry['sha256']:
                raise ValueError('ZIP content verification failed')
    return {'size': destination.stat().st_size, 'sha256': sha256(destination), 'files': files}


def source_commit(value):
    if not isinstance(value, str) or not re.fullmatch('[0-9a-f]{40}', value):
        raise ValueError('Verified immutable source commit is required')
    return value


def emit_candidates(stages, output, provenance):
    output = Path(output)
    game_commit = source_commit(provenance['gameSourceCommit'])
    runtime_commit = source_commit(provenance['runtime']['sourceCommit'])
    model_commit = source_commit(provenance['model']['sourceCommit'])
    required = {'game': 'EvidenceGenesis.exe', 'runtime': 'llama-server.exe', 'model': 'genesis.gguf'}
    for kind, filename in required.items():
        if not (Path(stages[kind]) / filename).is_file():
            raise ValueError('Required component file is missing: ' + filename)
    names = {
        'game': f'genesis-game-v{VERSION}-{game_commit[:12]}-windows-x64.zip',
        'runtime': f'genesis-runtime-{provenance["runtime"]["version"]}-{runtime_commit[:12]}-windows-x64.zip',
        'model': f'genesis-model-{provenance["model"]["version"]}-{model_commit[:12]}.zip',
    }
    packages = []
    for kind in ['game', 'runtime', 'model']:
        name = names[kind]
        if not re.fullmatch('[A-Za-z0-9._-]+', name):
            raise ValueError('Unsafe component artifact name')
        facts = deterministic_zip(stages[kind], output / name)
        packages.append({'kind': kind, 'path': name, **facts})
    components = {kind: {'version': provenance[kind]['version'],
                          'sourceCommit': provenance[kind]['sourceCommit'],
                          'licenseNotices': [{'name': notice['name'], 'url': None}
                                             for notice in provenance['licenses'] if notice['component'] == kind]}
                  for kind in ['runtime', 'model']}
    report = {'schema': 1, 'product': 'genesis', 'version': VERSION,
              'saveSchema': 4, 'minimumHubVersion': '0.3.0', 'sourceCommit': game_commit,
              'packages': packages, 'components': components, 'provenance': provenance}
    path = output / 'genesis-candidate-report.json'
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    return path


def verify_full_package_parity(full_archive, packages, provenance):
    """Match actual full-ZIP bytes to every component's verified file inventory."""
    with zipfile.ZipFile(full_archive) as archive:
        expected = {'EvidenceGenesis/SHA256SUMS.json'}
        for package in packages:
            for entry in package['files']:
                notice = any(item['component'] == package['kind'] and item['packagePath'] == entry['path']
                             for item in provenance['licenses'])
                if notice:
                    name = 'EvidenceGenesis/licenses/' + Path(entry['path']).name
                else:
                    prefix = {'game': '', 'runtime': 'brain/', 'model': 'model/'}[package['kind']]
                    name = 'EvidenceGenesis/' + prefix + entry['path']
                if name in expected:
                    raise ValueError('Duplicate component mapping in full package')
                expected.add(name)
                with archive.open(name) as stream:
                    actual = hashlib.file_digest(stream, 'sha256').hexdigest()
                if archive.getinfo(name).file_size != entry['size'] or actual != entry['sha256']:
                    raise ValueError('Full package/component byte parity failed')
        if set(archive.namelist()) != expected or len(archive.namelist()) != len(expected):
            raise ValueError('Unexpected full-package files')
