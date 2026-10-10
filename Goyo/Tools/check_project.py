import json
import plistlib
import re
import xml.etree.ElementTree as ET
from pathlib import Path

root=Path(__file__).resolve().parents[1]
pbx=(root/'Goyo.xcodeproj/project.pbxproj').read_text()
# Parse the generated OpenStep plist, including references in every build phase.
tokens=re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|\b\d+\b',re.sub(r'^//.*$', '', pbx, flags=re.M))
index=0
def token(expected):
    global index
    assert tokens[index]==expected, (index,tokens[index],expected)
    index+=1
def parse():
    global index
    current=tokens[index]
    if current=='{':
        token('{'); output={}
        while tokens[index]!='}':
            key=parse();token('=');output[key]=parse();token(';')
        token('}');return output
    if current=='(':
        token('(');output=[]
        while tokens[index]!=')':
            output.append(parse())
            if tokens[index]==',':token(',')
            else:break
        token(')');return output
    index+=1
    return json.loads(current) if current.startswith('"') else int(current)
project=parse()
assert index==len(tokens)
objects=project['objects']
assert objects[project['rootObject']]['isa']=='PBXProject'
by_name={o['name']:o for o in objects.values() if o.get('isa')=='PBXNativeTarget'}
assert set(by_name)=={'Goyo','GoyoBrowser','GoyoShieldConfiguration','GoyoShieldAction','GoyoActivityMonitor'}
for target in ['Goyo','GoyoBrowser']:
    phase=next(objects[p] for p in by_name[target]['buildPhases'] if objects[p]['isa']=='PBXSourcesBuildPhase')
    included={objects[objects[b]['fileRef']]['path'] for b in phase['files']}
    app_sources={str(p.relative_to(root)) for p in (root/'App').glob('*.swift')}
    assert app_sources<=included, (target,app_sources-included)
    assert 'Shared/AdultSites.swift' in included
    assert 'Shared/DcPolicy.swift' in included
    resources=next(objects[p] for p in by_name[target]['buildPhases'] if objects[p]['isa']=='PBXResourcesBuildPhase')
    resource_paths={objects[objects[b]['fileRef']]['path'] for b in resources['files']}
    assert {'Resources/Filters.js','Resources/DcPolicy.js','Resources/DcFilters.js','Resources/InstallPrompts.js','Resources/WhiteNoise.wav','Resources/AdRules.json','Resources/Assets.xcassets'}<=resource_paths
for path in re.findall(r'"path" = "([^"]+)";',pbx):
    if path.endswith(('.app','.appex')): continue
    assert (root/path).exists(), f'Missing project reference: {path}'
for target in ['Goyo','GoyoBrowser','GoyoShieldConfiguration','GoyoShieldAction','GoyoActivityMonitor']:
    info=plistlib.loads((root/f'{target}-Info.plist').read_bytes())
    assert info['CFBundleIdentifier']=='$(PRODUCT_BUNDLE_IDENTIFIER)'
    if target not in ['Goyo','GoyoBrowser']: assert info['NSExtension']['NSExtensionPrincipalClass'].startswith('$(PRODUCT_MODULE_NAME).')
    if target!='GoyoBrowser':
        ent=plistlib.loads((root/f'{target}.entitlements').read_bytes())
        assert ent['com.apple.developer.family-controls'] is True
        assert ent['com.apple.security.application-groups']==['$(GOYO_APP_GROUP)']
for scheme in ['Goyo','GoyoBrowser']:
    tree=ET.parse(root/f'Goyo.xcodeproj/xcshareddata/xcschemes/{scheme}.xcscheme')
    assert tree.find('.//BuildableReference').attrib['BlueprintName']==scheme
assert len(json.loads((root/'Resources/AdRules.json').read_text()))==4
assert (root/'Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png').exists()
assert 'WEB_ONLY' in pbx
assert 'Embed App Extensions' in pbx
assert all((root/f'Resources/Assets.xcassets/{name}.appiconset/{name}.png').exists() for name in ['IconGreen','IconNight','IconPaper'])
assert all((root/p).exists() for p in ['README-KO.md','VALIDATION.md','LICENSE'])
print('PASS: OpenStep PBX syntax, both app targets include all app sources, resources, five plists, four entitlements, two schemes, icon and documents.')
