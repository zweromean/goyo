#!/usr/bin/env python3
"""Launch the real full app on iPhone Simulator and capture two screens."""
import argparse
import json
import os
import subprocess
import time
from pathlib import Path


def command(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout.strip()


def smoke(app, destination):
    devices = json.loads(command('xcrun', 'simctl', 'list', 'devices', 'available', '-j'))['devices']
    choices = [d for group in devices.values() for d in group if d.get('isAvailable') and d['name'].startswith('iPhone')]
    if not choices: raise RuntimeError('No available iPhone simulator runtime.')
    device = choices[0]['udid']; bundle = 'app.goyo.detox'
    destination.mkdir(parents=True, exist_ok=True)
    if choices[0]['state'] != 'Booted': command('xcrun', 'simctl', 'boot', device)
    command('xcrun', 'simctl', 'bootstatus', device, '-b')
    command('xcrun', 'simctl', 'status_bar', device, 'override', '--time', '12:19', '--batteryState', 'charged', '--batteryLevel', '100')
    command('xcrun', 'simctl', 'install', device, str(app))
    def capture(name, *arguments):
        command('xcrun', 'simctl', 'launch', '--terminate-running-process', device, bundle, *arguments)
        time.sleep(8)
        jobs = command('xcrun', 'simctl', 'spawn', device, 'launchctl', 'list')
        live = [line for line in jobs.splitlines() if 'UIKitApplication:' + bundle + '[' in line and line.split()[0].isdigit()]
        if not live:
            raise RuntimeError(f'{name}: full app exited after launch.')
        command('xcrun', 'simctl', 'io', device, 'screenshot', str(destination / f'{name}.png'))
    try:
        capture('Goyo-home')
        capture('Goyo-study', '--goyo-smoke-study')
        (destination / 'result.json').write_text(json.dumps({'app': 'Goyo', 'device': choices[0]['name'], 'screens': ['home', 'study'], 'launch_survived_seconds': 8, 'scope': 'Simulator launch smoke check. Does not verify real-device Screen Time authorization or blocking.'}, indent=2))
        print('PASS: full Goyo survived home and study launches on iPhone Simulator.')
    finally:
        subprocess.run(['xcrun', 'simctl', 'shutdown', device], capture_output=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path); parser.add_argument('destination', type=Path)
    args = parser.parse_args(); smoke(args.app, args.destination)
