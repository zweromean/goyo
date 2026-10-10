import datetime
import importlib.util
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('goyo_sign', Path(__file__).resolve().parents[1] / 'Tools/sign_device_app.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)


class ProfileValidationTests(unittest.TestCase):
    def fixture(self, root, mutate=lambda p, i: None, extension_count=3):
        app = root / 'Goyo.app'; app.mkdir()
        groups = ['group.test.goyo']; ids = ['test.goyo'] + ['test.goyo.' + suffix for suffix in ['shieldconfiguration', 'shieldaction', 'activitymonitor'][:extension_count]]
        bundles = [app]
        for i in range(extension_count):
            bundle = app / 'PlugIns' / ('Extension' + str(i) + '.appex'); bundle.mkdir(parents=True); bundles.append(bundle)
        profiles = root / 'profiles.zip'
        with zipfile.ZipFile(profiles, 'w') as archive:
            for i, (bundle, identifier) in enumerate(zip(bundles, ids)):
                (bundle / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': identifier, 'GoyoAppGroup': groups[0]}))
                profile = {'Entitlements': {'application-identifier': 'TEAM.' + identifier, 'com.apple.developer.team-identifier': 'TEAM', 'com.apple.developer.family-controls': True, 'com.apple.security.application-groups': groups}, 'ExpirationDate': datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) + datetime.timedelta(days=7), 'ProvisionedDevices': ['fixture-device']}
                mutate(profile, i); archive.writestr(str(i) + '.mobileprovision', plistlib.dumps(profile))
        return app, profiles

    def reject(self, mutate, message, extension_count=3):
        with tempfile.TemporaryDirectory() as directory:
            app, profiles = self.fixture(Path(directory), mutate, extension_count)
            with patch.object(module, 'decoded_profile', plistlib.loads), patch.object(module.subprocess, 'run') as command:
                with self.assertRaisesRegex(ValueError, message): module.sign(app, profiles, 'test-identity')
                command.assert_not_called()
                self.assertFalse(list(app.rglob('embedded.mobileprovision')))

    def test_missing_family_entitlement(self):
        self.reject(lambda p, i: p['Entitlements'].pop('com.apple.developer.family-controls') if i == 1 else None, 'Family Controls')
    def test_expired_profile(self):
        self.reject(lambda p, i: p.update(ExpirationDate=datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) - datetime.timedelta(days=1)) if i == 2 else None, 'Expired')
    def test_wrong_group(self):
        self.reject(lambda p, i: p['Entitlements'].update({'com.apple.security.application-groups': ['group.other']}) if i == 3 else None, 'App Group')
    def test_mixed_teams(self):
        self.reject(lambda p, i: p['Entitlements'].update({'com.apple.developer.team-identifier': 'OTHER'}) if i == 2 else None, 'same App Group and Apple team')
    def test_store_profile_not_direct_install(self):
        self.reject(lambda p, i: p.pop('ProvisionedDevices') if i == 0 else None, 'registered-device')
    def test_extension_missing(self):
        self.reject(lambda p, i: None, 'all three', extension_count=2)
    def test_wrong_bundle(self):
        self.reject(lambda p, i: p['Entitlements'].update({'application-identifier': 'TEAM.other.test.goyo'}) if i == 0 else None, 'explicit provisioning')
    def test_valid_profiles_sign_extensions_first(self):
        with tempfile.TemporaryDirectory() as directory:
            app, profiles = self.fixture(Path(directory))
            with patch.object(module, 'decoded_profile', plistlib.loads), patch.object(module.subprocess, 'run') as command, patch('builtins.print'):
                module.sign(app, profiles, 'test-identity')
                calls = [call.args[0] for call in command.call_args_list if '--sign' in call.args[0]]
                self.assertEqual(len(calls), 4)
                self.assertEqual(calls[-1][-1], str(app))
                self.assertEqual(len(list(app.rglob('embedded.mobileprovision'))), 4)


if __name__ == '__main__': unittest.main()
