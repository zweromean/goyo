#!/usr/bin/env python3
"""Package a device .app as an unsigned IPA for local re-signing."""
import argparse
import plistlib
import zipfile
from pathlib import Path


def package(app: Path, output: Path):
    if not app.is_dir() or app.suffix != '.app':
        raise ValueError(f'App bundle missing: {app}')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if 'iPhoneOS' not in info.get('CFBundleSupportedPlatforms', []):
        raise ValueError('A physical iPhone build is required; simulator apps cannot be installed.')
    executable = info.get('CFBundleExecutable')
    if not executable or not (app / executable).is_file():
        raise ValueError('Compiled app executable missing')
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix('.tmp')
    try:
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
            for file in sorted(app.rglob('*')):
                if file.is_symlink():
                    raise ValueError(f'Unexpected symlink: {file}')
                if file.is_file():
                    archive.write(file, Path('Payload') / app.name / file.relative_to(app))
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None:
                raise ValueError('IPA archive integrity failure')
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    print(output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    package(args.app, args.output)
