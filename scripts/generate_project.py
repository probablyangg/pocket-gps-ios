#!/usr/bin/env python3
"""Regenerate the included dependency-free Xcode project, if needed."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def add(key_name, isa, **values):
    key = ident(key_name)
    objects[key] = dict(isa=isa, **values)
    return key

def encode(value, indent=0):
    if isinstance(value, dict):
        return '{\n' + ''.join('\t' * (indent+1) + json.dumps(k) + ' = ' + encode(v, indent+1) + ';\n' for k, v in value.items()) + '\t' * indent + '}'
    if isinstance(value, list):
        return '( ' + ', '.join(encode(v, indent) for v in value) + (' ' if value else '') + ')'
    if isinstance(value, int): return str(value)
    return json.dumps(str(value))

source_names = ['ExplorInkGPSApp.swift', 'ContentView.swift', 'GPSBridge.swift', 'PositionCodec.c']
header_names = ['PositionCodec.h', 'ExplorInkGPS-Bridging-Header.h', 'Info.plist', 'PrivacyInfo.xcprivacy']
refs = []
sources = []
resources = []
for name in source_names + header_names:
    suffix = Path(name).suffix
    kind = {'.swift':'sourcecode.swift', '.c':'sourcecode.c.c', '.h':'sourcecode.c.h', '.plist':'text.plist.xml', '.xcprivacy':'text.xml'}[suffix]
    ref = add('file-'+name, 'PBXFileReference', lastKnownFileType=kind, path=name, sourceTree='<group>')
    refs.append(ref)
    if name in source_names:
        sources.append(add('build-'+name, 'PBXBuildFile', fileRef=ref))
    if suffix == '.xcprivacy':
        resources.append(add('resource-'+name, 'PBXBuildFile', fileRef=ref))
product = add('product', 'PBXFileReference', explicitFileType='wrapper.application', includeInIndex=0,
              path='ExplorInkGPS.app', sourceTree='BUILT_PRODUCTS_DIR')
app_group = add('app-group', 'PBXGroup', children=refs, path='ExplorInkGPS', sourceTree='<group>')
products = add('products', 'PBXGroup', children=[product], name='Products', sourceTree='<group>')
main = add('main', 'PBXGroup', children=[app_group, products], sourceTree='<group>')
phases = [add('sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=sources, runOnlyForDeploymentPostprocessing=0),
          add('frameworks', 'PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0),
          add('resources', 'PBXResourcesBuildPhase', buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)]
project_configs = []
target_configs = []
for configuration in ['Debug', 'Release']:
    project_configs.append(add('project-'+configuration, 'XCBuildConfiguration', name=configuration, buildSettings={
        'CLANG_ENABLE_MODULES':'YES', 'CLANG_ENABLE_OBJC_ARC':'YES', 'SDKROOT':'iphoneos',
        'IPHONEOS_DEPLOYMENT_TARGET':'17.0', 'GCC_C_LANGUAGE_STANDARD':'c11',
        'GCC_WARN_64_TO_32_BIT_CONVERSION':'YES', 'SWIFT_VERSION':'5.0',
        'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if configuration == 'Debug' else '-O',
        'DEBUG_INFORMATION_FORMAT':'dwarf' if configuration == 'Debug' else 'dwarf-with-dsym',
        'ENABLE_TESTABILITY':'YES' if configuration == 'Debug' else 'NO'}))
    target_configs.append(add('target-'+configuration, 'XCBuildConfiguration', name=configuration, buildSettings={
        'PRODUCT_NAME':'$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER':'com.example.explorink.pocketgps',
        'INFOPLIST_FILE':'ExplorInkGPS/Info.plist', 'GENERATE_INFOPLIST_FILE':'NO',
        'SWIFT_OBJC_BRIDGING_HEADER':'ExplorInkGPS/ExplorInkGPS-Bridging-Header.h',
        'TARGETED_DEVICE_FAMILY':'1', 'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator',
        'SUPPORTS_MACCATALYST':'NO', 'CODE_SIGN_STYLE':'Automatic',
        'LD_RUNPATH_SEARCH_PATHS':['$(inherited)', '@executable_path/Frameworks']}))
project_list = add('project-list', 'XCConfigurationList', buildConfigurations=project_configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')
target_list = add('target-list', 'XCConfigurationList', buildConfigurations=target_configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')
target = add('target', 'PBXNativeTarget', buildConfigurationList=target_list, buildPhases=phases,
             buildRules=[], dependencies=[], name='ExplorInkGPS', productName='ExplorInkGPS',
             productReference=product, productType='com.apple.product-type.application')
project = add('project', 'PBXProject', attributes={'LastUpgradeCheck':'1600'}, buildConfigurationList=project_list,
              compatibilityVersion='Xcode 14.0', developmentRegion='en', hasScannedForEncodings=0,
              knownRegions=['en', 'Base'], mainGroup=main, productRefGroup=products,
              projectDirPath='', projectRoot='', targets=[target])
project_dir = ROOT / 'ExplorInkGPS.xcodeproj'
project_dir.mkdir(exist_ok=True)
(project_dir / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + encode(dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)) + '\n')
scheme_dir = project_dir / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="ExplorInkGPS.app" BlueprintName="ExplorInkGPS" ReferencedContainer="container:ExplorInkGPS.xcodeproj"/>'
(scheme_dir / 'ExplorInkGPS.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(project_dir)
