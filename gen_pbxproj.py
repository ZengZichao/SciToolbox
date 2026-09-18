#!/usr/bin/env python3
"""生成 SciToolbox.xcodeproj/project.pbxproj

采用 Xcode 16+ 的 PBXFileSystemSynchronizedRootGroup：
用一条条目引用整个 Sources/SciToolbox 目录，日后新增源文件无需改动工程文件。
"""
import os

C = [0]
IDS = {}


def uid(name):
    if name not in IDS:
        C[0] += 1
        IDS[name] = "A1%022X" % C[0]
        assert len(IDS[name]) == 24, IDS[name]
    return IDS[name]


def q(s):
    return '"%s"' % s


TARGET_NAME = "SciToolbox"
BUNDLE_ID = "com.scitoolbox.app"
TEAM_ID = "D93V4997DT"
DEPLOY_TARGET = "15.0"
MARKETING_VERSION = "1.0.0"
BUILD_NUMBER = "2"
SWIFT_VERSION = "5.0"

COMMON = f"""				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MACOSX_DEPLOYMENT_TARGET = {DEPLOY_TARGET};
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				SDKROOT = macosx;
				SWIFT_VERSION = {SWIFT_VERSION};
"""

PROJ_DEBUG = COMMON + """				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
"""

PROJ_RELEASE = COMMON + """				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				MTL_ENABLE_DEBUG_INFO = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
"""

TARGET_COMMON = f"""				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = App/{TARGET_NAME}.entitlements;
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = {BUILD_NUMBER};
				DEVELOPMENT_TEAM = {TEAM_ID};
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = App/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = {MARKETING_VERSION};
				PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_VERSION = {SWIFT_VERSION};
"""

TARGET_DEBUG = TARGET_COMMON + """				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
"""
TARGET_RELEASE = TARGET_COMMON

pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{uid('BF_ASSETS')} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {uid('FR_ASSETS')} /* Assets.xcassets */; }};
		{uid('BF_PRIVACY')} /* PrivacyInfo.xcprivacy in Resources */ = {{isa = PBXBuildFile; fileRef = {uid('FR_PRIVACY')} /* PrivacyInfo.xcprivacy */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{uid('FR_PRODUCT')} /* {TARGET_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {TARGET_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{uid('FR_INFO')} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
		{uid('FR_ENTITLEMENTS')} /* {TARGET_NAME}.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = {TARGET_NAME}.entitlements; sourceTree = "<group>"; }};
		{uid('FR_ASSETS')} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};
		{uid('FR_PRIVACY')} /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{uid('SYNCGROUP')} /* {TARGET_NAME} */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Sources/{TARGET_NAME};
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{uid('PHASE_FRAMEWORKS')} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{uid('MAINGROUP')} = {{
			isa = PBXGroup;
			children = (
				{uid('APPGROUP')} /* App */,
				{uid('SYNCGROUP')} /* {TARGET_NAME} */,
				{uid('PRODUCTSGROUP')} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{uid('PRODUCTSGROUP')} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{uid('FR_PRODUCT')} /* {TARGET_NAME}.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
		{uid('APPGROUP')} /* App */ = {{
			isa = PBXGroup;
			children = (
				{uid('FR_ASSETS')} /* Assets.xcassets */,
				{uid('FR_INFO')} /* Info.plist */,
				{uid('FR_PRIVACY')} /* PrivacyInfo.xcprivacy */,
				{uid('FR_ENTITLEMENTS')} /* {TARGET_NAME}.entitlements */,
			);
			path = App;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{uid('TARGET')} /* {TARGET_NAME} */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {uid('CFGLIST_TARGET')} /* Build configuration list for PBXNativeTarget "{TARGET_NAME}" */;
			buildPhases = (
				{uid('PHASE_SOURCES')} /* Sources */,
				{uid('PHASE_FRAMEWORKS')} /* Frameworks */,
				{uid('PHASE_RESOURCES')} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{uid('SYNCGROUP')} /* {TARGET_NAME} */,
			);
			name = {TARGET_NAME};
			packageProductDependencies = (
			);
			productName = {TARGET_NAME};
			productReference = {uid('FR_PRODUCT')} /* {TARGET_NAME}.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{uid('PROJECT')} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {{
					{uid('TARGET')} = {{
						CreatedOnToolsVersion = 16.0;
					}};
				}};
			}};
			buildConfigurationList = {uid('CFGLIST_PROJECT')} /* Build configuration list for PBXProject "{TARGET_NAME}" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
				"zh-Hans",
			);
			mainGroup = {uid('MAINGROUP')};
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = {uid('PRODUCTSGROUP')} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{uid('TARGET')} /* {TARGET_NAME} */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{uid('PHASE_RESOURCES')} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{uid('BF_ASSETS')} /* Assets.xcassets in Resources */,
				{uid('BF_PRIVACY')} /* PrivacyInfo.xcprivacy in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{uid('PHASE_SOURCES')} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{uid('CFG_PROJ_DEBUG')} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{PROJ_DEBUG}			}};
			name = Debug;
		}};
		{uid('CFG_PROJ_RELEASE')} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{PROJ_RELEASE}			}};
			name = Release;
		}};
		{uid('CFG_TGT_DEBUG')} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{TARGET_DEBUG}			}};
			name = Debug;
		}};
		{uid('CFG_TGT_RELEASE')} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{TARGET_RELEASE}			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{uid('CFGLIST_PROJECT')} /* Build configuration list for PBXProject "{TARGET_NAME}" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{uid('CFG_PROJ_DEBUG')} /* Debug */,
				{uid('CFG_PROJ_RELEASE')} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{uid('CFGLIST_TARGET')} /* Build configuration list for PBXNativeTarget "{TARGET_NAME}" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{uid('CFG_TGT_DEBUG')} /* Debug */,
				{uid('CFG_TGT_RELEASE')} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {uid('PROJECT')} /* Project object */;
}}
"""

SCHEME = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{uid('TARGET')}"
               BuildableName = "{TARGET_NAME}.app"
               BlueprintName = "{TARGET_NAME}"
               ReferencedContainer = "container:{TARGET_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{uid('TARGET')}"
            BuildableName = "{TARGET_NAME}.app"
            BlueprintName = "{TARGET_NAME}"
            ReferencedContainer = "container:{TARGET_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{uid('TARGET')}"
            BuildableName = "{TARGET_NAME}.app"
            BlueprintName = "{TARGET_NAME}"
            ReferencedContainer = "container:{TARGET_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

ROOT = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.join(ROOT, f"{TARGET_NAME}.xcodeproj")
os.makedirs(os.path.join(PROJ, "xcshareddata", "xcschemes"), exist_ok=True)

with open(os.path.join(PROJ, "project.pbxproj"), "w", encoding="utf-8") as f:
    f.write(pbx)
with open(os.path.join(PROJ, "xcshareddata", "xcschemes", f"{TARGET_NAME}.xcscheme"), "w", encoding="utf-8") as f:
    f.write(SCHEME)

print("已生成:")
print("  ", os.path.join(PROJ, "project.pbxproj"))
print("  ", os.path.join(PROJ, "xcshareddata", "xcschemes", f"{TARGET_NAME}.xcscheme"))
print()
print("对象 ID 分配:")
for k, v in IDS.items():
    print(f"  {k:18s} {v}  ({len(v)} chars)")
