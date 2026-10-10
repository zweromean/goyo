#!/usr/bin/env python3
"""Generate a self-contained Xcode project; no XcodeGen dependency."""
import hashlib
import json
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}
def ident(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def add(key, **value):
    uid = ident(key)
    objects[uid] = value
    return uid
def write_plist(path, value):
    (ROOT / path).write_bytes(plistlib.dumps(value, sort_keys=False))

main_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'App').glob('*.swift'))
shared_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'Shared').glob('*.swift'))
targets = {
    'Goyo': dict(kind='app', sources=main_sources+shared_sources, bundle='$(GOYO_BUNDLE_ID)', family=True, resources=True),
    'GoyoBrowser': dict(kind='app', sources=main_sources+shared_sources, bundle='$(GOYO_BUNDLE_ID).browser', family=False, resources=True),
    'GoyoShieldConfiguration': dict(kind='extension', sources=['Extensions/ShieldConfiguration/ShieldConfiguration.swift','Shared/Preferences.swift'], bundle='$(GOYO_BUNDLE_ID).shieldconfiguration', family=True, extension='com.apple.ManagedSettingsUI.shield-configuration-service', principal='ShieldConfigurationExtension'),
    'GoyoShieldAction': dict(kind='extension', sources=['Extensions/ShieldAction/ShieldAction.swift','Shared/Preferences.swift'], bundle='$(GOYO_BUNDLE_ID).shieldaction', family=True, extension='com.apple.ManagedSettings.shield-action-service', principal='ShieldActionExtension'),
    'GoyoActivityMonitor': dict(kind='extension', sources=['Extensions/ActivityMonitor/ActivityMonitor.swift']+shared_sources, bundle='$(GOYO_BUNDLE_ID).activitymonitor', family=True, extension='com.apple.deviceactivity.monitor-extension', principal='ActivityMonitorExtension'),
}
for name, spec in targets.items():
    info = dict(CFBundleDevelopmentRegion='ko',CFBundleDisplayName='고요' if spec['kind']=='app' else name,
                CFBundleExecutable='$(EXECUTABLE_NAME)',CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',
                CFBundleInfoDictionaryVersion='6.0',CFBundleName='$(PRODUCT_NAME)',
                CFBundlePackageType='APPL' if spec['kind']=='app' else 'XPC!',
                CFBundleShortVersionString='$(MARKETING_VERSION)',CFBundleVersion='$(CURRENT_PROJECT_VERSION)')
    if spec['family']: info['GoyoAppGroup']='$(GOYO_APP_GROUP)'
    if spec['kind']=='app':
        info.update(LSRequiresIPhoneOS=True,UILaunchScreen={},
                    UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait'],
                    **{'UISupportedInterfaceOrientations~ipad':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight']})
        info['NSCameraUsageDescription']='인스타그램 웹 기능에서 카메라를 사용할 때 필요합니다.'
        info['NSMicrophoneUsageDescription']='인스타그램 웹 기능에서 음성을 사용할 때 필요합니다.'
    else:
        info['NSExtension']={'NSExtensionPointIdentifier':spec['extension'],'NSExtensionPrincipalClass':'$(PRODUCT_MODULE_NAME).'+spec['principal']}
    write_plist(f'{name}-Info.plist',info)
    if spec['family']:
        write_plist(f'{name}.entitlements',{'com.apple.developer.family-controls':True,'com.apple.security.application-groups':['$(GOYO_APP_GROUP)']})

source_refs = {}
app_resources = ['Resources/Filters.js','Resources/DcPolicy.js','Resources/DcFilters.js','Resources/AdRules.json','Resources/InstallPrompts.js','Resources/WhiteNoise.wav','Resources/Assets.xcassets']
paths = set(main_sources+shared_sources+app_resources+['Config.xcconfig'])
for spec in targets.values(): paths.update(spec['sources'])
for name,spec in targets.items():
    paths.add(f'{name}-Info.plist')
    if spec['family']: paths.add(f'{name}.entitlements')
for path in sorted(paths):
    ext = Path(path).suffix
    typ = {'.swift':'sourcecode.swift','.json':'text.json','.plist':'text.plist.xml','.entitlements':'text.plist.entitlements','.xcconfig':'text.xcconfig','.xcassets':'folder.assetcatalog'}.get(ext,'text')
    source_refs[path] = add('file:'+path,isa='PBXFileReference',lastKnownFileType=typ,path=path,sourceTree='<group>')

products=[]
target_ids={name:ident('target:'+name) for name in targets}
for name,spec in targets.items():
    app=spec['kind']=='app'
    product=add('product:'+name,isa='PBXFileReference',explicitFileType='wrapper.application' if app else 'wrapper.app-extension',includeInIndex=0,path=name+('.app' if app else '.appex'),sourceTree='BUILT_PRODUCTS_DIR')
    products.append(product)
    sources=[]
    for path in spec['sources']:
        sources.append(add('build:'+name+':'+path,isa='PBXBuildFile',fileRef=source_refs[path]))
    sourcephase=add('sourcephase:'+name,isa='PBXSourcesBuildPhase',buildActionMask=2147483647,files=sources,runOnlyForDeploymentPostprocessing=0)
    frameworkphase=add('frameworkphase:'+name,isa='PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
    resources=[]
    if spec.get('resources'):
        for path in app_resources:
            resources.append(add('resource:'+name+':'+path,isa='PBXBuildFile',fileRef=source_refs[path]))
    resourcephase=add('resourcephase:'+name,isa='PBXResourcesBuildPhase',buildActionMask=2147483647,files=resources,runOnlyForDeploymentPostprocessing=0)
    phases=[sourcephase,frameworkphase,resourcephase]
    dependencies=[]
    if name=='Goyo':
        embedded=[]
        for extension in ['GoyoShieldConfiguration','GoyoShieldAction','GoyoActivityMonitor']:
            extproduct=ident('product:'+extension)
            embedded.append(add('embed:'+extension,isa='PBXBuildFile',fileRef=extproduct,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']}))
            proxy=add('proxy:'+extension,isa='PBXContainerItemProxy',containerPortal=ident('project'),proxyType=1,remoteGlobalIDString=target_ids[extension],remoteInfo=extension)
            dependencies.append(add('dependency:'+extension,isa='PBXTargetDependency',target=target_ids[extension],targetProxy=proxy))
        phases.append(add('embedphase',isa='PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=embedded,name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0))
    configs=[]
    for mode in ['Debug','Release']:
        settings={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':spec['bundle'],'INFOPLIST_FILE':f'{name}-Info.plist','GENERATE_INFOPLIST_FILE':'NO','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O',
                  'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'] + ([] if app else ['@executable_path/../../Frameworks'])}
        if spec['family']: settings['CODE_SIGN_ENTITLEMENTS']=f'{name}.entitlements'
        if not app: settings.update(APPLICATION_EXTENSION_API_ONLY='YES',SKIP_INSTALL='YES')
        else:
            settings['ASSETCATALOG_COMPILER_APPICON_NAME']='AppIcon'
            settings['ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES']=['IconGreen','IconNight','IconPaper']
            settings['ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS']='YES'
        flags=['$(inherited)']
        if mode=='Debug': flags.append('DEBUG')
        if name=='GoyoBrowser': flags.append('WEB_ONLY')
        settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']=flags
        configs.append(add('config:'+name+':'+mode,isa='XCBuildConfiguration',baseConfigurationReference=source_refs['Config.xcconfig'],buildSettings=settings,name=mode))
    configlist=add('configlist:'+name,isa='XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
    add('target:'+name,isa='PBXNativeTarget',buildConfigurationList=configlist,buildPhases=phases,buildRules=[],dependencies=dependencies,name=name,productName=name,productReference=product,productType='com.apple.product-type.application' if app else 'com.apple.product-type.app-extension')

productgroup=add('productgroup',isa='PBXGroup',children=products,name='Products',sourceTree='<group>')
rootgroup=add('rootgroup',isa='PBXGroup',children=list(source_refs.values())+[productgroup],sourceTree='<group>')
projectconfigs=[]
for mode in ['Debug','Release']:
    projectconfigs.append(add('projectconfig:'+mode,isa='XCBuildConfiguration',baseConfigurationReference=source_refs['Config.xcconfig'],buildSettings={},name=mode))
projectconfiglist=add('projectconfiglist',isa='XCConfigurationList',buildConfigurations=projectconfigs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
project=add('project',isa='PBXProject',attributes={'LastUpgradeCheck':'1600'},buildConfigurationList=projectconfiglist,compatibilityVersion='Xcode 14.0',developmentRegion='ko',hasScannedForEncodings=0,knownRegions=['ko','en','Base'],mainGroup=rootgroup,productRefGroup=productgroup,projectDirPath='',projectRoot='',targets=list(target_ids.values()))

def serialize(value, depth=0):
    if isinstance(value,dict):
        return '{\n'+''.join('\t'*(depth+1)+json.dumps(k)+' = '+serialize(v,depth+1)+';\n' for k,v in value.items())+'\t'*depth+'}'
    if isinstance(value,list): return '('+','.join(serialize(x,depth+1) for x in value)+')'
    if isinstance(value,int): return str(value)
    return json.dumps(value,ensure_ascii=False)

directory=ROOT/'Goyo.xcodeproj'
directory.mkdir(exist_ok=True)
(directory/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
schemes=directory/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
for name in ['Goyo','GoyoBrowser']:
    ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_ids[name]}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:Goyo.xcodeproj"/>'
    (schemes/f'{name}.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(f'Generated {directory} with {len(targets)} targets.')
