#!/usr/bin/env python3
"""Re-sign the full device build using four entitlement-bearing profiles."""
import argparse
import datetime
import plistlib
import subprocess
import tempfile
import zipfile
from pathlib import Path


def decoded_profile(data):
    with tempfile.NamedTemporaryFile(suffix='.mobileprovision') as f:
        f.write(data); f.flush()
        result = subprocess.run(['security', 'cms', '-D', '-i', f.name], check=True, capture_output=True)
    return plistlib.loads(result.stdout)


def sign(app, profile_zip, identity):
    bundles = [app] + sorted((app / 'PlugIns').glob('*.appex'))
    if len(bundles) != 4:
        raise ValueError('Full Goyo app must contain all three Screen Time extensions.')
    profiles = {}
    with zipfile.ZipFile(profile_zip) as archive:
        for name in archive.namelist():
            if not name.endswith('.mobileprovision') or name.startswith('__MACOSX/'):
                continue
            data = archive.read(name); profile = decoded_profile(data)
            profiles[profile['Entitlements']['application-identifier']] = (profile, data)
    prepared = []; shared_group = None; shared_team = None
    now = datetime.datetime.now(datetime.timezone.utc)
    for bundle in bundles:
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        bundle_id = info['CFBundleIdentifier']
        matches = [(profile, data) for key, (profile, data) in profiles.items() if key.split('.', 1)[-1] == bundle_id]
        if len(matches) != 1:
            raise ValueError(f'One explicit provisioning profile is required for {bundle_id}.')
        profile, data = matches[0]; ent = profile['Entitlements']
        if not ent.get('com.apple.developer.family-controls'):
            raise ValueError(f'Family Controls entitlement missing for {bundle_id}; signing cannot enable it.')
        groups = ent.get('com.apple.security.application-groups', [])
        team = ent.get('com.apple.developer.team-identifier')
        group = info.get('GoyoAppGroup')
        if not group or group not in groups or not team:
            raise ValueError(f'App Group or team mismatch for {bundle_id}.')
        if shared_group is not None and (group != shared_group or team != shared_team):
            raise ValueError('All targets must share the same App Group and Apple team.')
        shared_group, shared_team = group, team
        if profile['ExpirationDate'].replace(tzinfo=datetime.timezone.utc) <= now:
            raise ValueError(f'Expired provisioning profile for {bundle_id}.')
        if not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices'):
            raise ValueError('A development or registered-device profile is required for direct iPhone installation.')
        prepared.append((bundle, ent, data))
    # All profiles are validated before modifying the bundle.
    for framework in sorted((app / 'Frameworks').glob('*')):
        subprocess.run(['codesign', '--force', '--sign', identity, str(framework)], check=True)
    with tempfile.TemporaryDirectory(prefix='goyo-sign-') as directory:
        for bundle, ent, data in reversed(prepared):
            (bundle / 'embedded.mobileprovision').write_bytes(data)
            entitlement_path = Path(directory) / (bundle.name + '.plist')
            entitlement_path.write_bytes(plistlib.dumps(ent))
            subprocess.run(['codesign', '--force', '--sign', identity, '--entitlements', str(entitlement_path), '--generate-entitlement-der', str(bundle)], check=True)
            subprocess.run(['codesign', '--verify', '--strict', str(bundle)], check=True)
    print('Signed full Goyo and three extensions with validated Family Controls profiles.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path); parser.add_argument('profiles', type=Path); parser.add_argument('identity')
    args = parser.parse_args(); sign(args.app, args.profiles, args.identity)
