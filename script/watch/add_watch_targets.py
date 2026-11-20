# Adds a watchOS capture app and its complication extension to an Xcode project by editing
# project.pbxproj directly (written Nov 20, 2026 for SAVY, run once; no Xcode was available).
# To reuse for another app: change the bundle IDs, team, display name, group anchor lines and
# the file names below, then run: python3 -I add_watch_targets.py <App>.xcodeproj/project.pbxproj
# and check the result with check_pbxproj.py. Running it twice on one project adds duplicates.
import re, sys, hashlib

path = sys.argv[1]
s = open(path).read()
existing = set(re.findall(r'\b[0-9A-F]{24}\b', s))

def gid(name):
    # Deterministic, collision-checked 24-hex IDs.
    n = 0
    while True:
        h = hashlib.sha1(f"savy-watch:{name}:{n}".encode()).hexdigest().upper()[:24]
        if h not in existing:
            existing.add(h)
            return h
        n += 1

I = {k: gid(k) for k in [
    # file refs
    "fr_capture", "fr_importer", "fr_wapp", "fr_wstore", "fr_wviews", "fr_wintents", "fr_wassets", "fr_went",
    "fr_wwswift", "fr_wwinfo", "prod_watch", "prod_widgets",
    # build files
    "bf_ios_capture", "bf_ios_importer",
    "bf_w_capture", "bf_w_app", "bf_w_store", "bf_w_views", "bf_w_intents", "bf_w_assets", "bf_w_embed",
    "bf_ww_swift",
    # phases
    "w_sources", "w_frameworks", "w_resources", "w_embed",
    "ww_sources", "ww_frameworks", "ww_resources",
    # groups
    "g_watch", "g_widgets",
    # targets
    "t_watch", "t_widgets",
    # deps
    "proxy_widgets", "dep_widgets",
    # configs
    "cl_watch", "c_watch_debug", "c_watch_release",
    "cl_widgets", "c_widgets_debug", "c_widgets_release",
]}

def insert_before(marker, text):
    global s
    assert s.count(marker) == 1, marker
    s = s.replace(marker, text + marker)

# --- PBXBuildFile
bf = f"""		{I['bf_ios_capture']} /* WatchCapture.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['fr_capture']} /* WatchCapture.swift */; }};
		{I['bf_ios_importer']} /* WatchCaptureImporter.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['fr_importer']} /* WatchCaptureImporter.swift */; }};
		{I['bf_w_capture']} /* WatchCapture.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['fr_capture']} /* WatchCapture.swift */; }};
		{I['bf_w_app']} /* SAVYWatchApp.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['fr_wapp']} /* SAVYWatchApp.swift */; }};
		{I['bf_w_store']} /* WatchCaptureStore.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['fr_wstore']} /* WatchCaptureStore.swift */; }};
		{I['bf_w_views']} /* CaptureViews.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['fr_wviews']} /* CaptureViews.swift */; }};
		{I['bf_w_intents']} /* CaptureIntents.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['fr_wintents']} /* CaptureIntents.swift */; }};
		{I['bf_w_assets']} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {I['fr_wassets']} /* Assets.xcassets */; }};
		{I['bf_w_embed']} /* SAVYWatchWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {I['prod_widgets']} /* SAVYWatchWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
		{I['bf_ww_swift']} /* SAVYWatchWidgets.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {I['fr_wwswift']} /* SAVYWatchWidgets.swift */; }};
"""
insert_before("/* End PBXBuildFile section */", bf)

# --- PBXContainerItemProxy
proxy = f"""		{I['proxy_widgets']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = 3DA3A1EAB03B2D0873868AC9 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {I['t_widgets']};
			remoteInfo = SAVYWatchWidgets;
		}};
"""
insert_before("/* End PBXContainerItemProxy section */", proxy)

# --- PBXCopyFilesBuildPhase (new section, placed before PBXFileReference)
copy = f"""/* Begin PBXCopyFilesBuildPhase section */
		{I['w_embed']} /* Embed Foundation Extensions */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				{I['bf_w_embed']} /* SAVYWatchWidgets.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

"""
assert "PBXCopyFilesBuildPhase section" not in s
insert_before("/* Begin PBXFileReference section */", copy)

# --- PBXFileReference
fr = f"""		{I['fr_capture']} /* WatchCapture.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchCapture.swift; sourceTree = "<group>"; }};
		{I['fr_importer']} /* WatchCaptureImporter.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchCaptureImporter.swift; sourceTree = "<group>"; }};
		{I['fr_wapp']} /* SAVYWatchApp.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SAVYWatchApp.swift; sourceTree = "<group>"; }};
		{I['fr_wstore']} /* WatchCaptureStore.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchCaptureStore.swift; sourceTree = "<group>"; }};
		{I['fr_wviews']} /* CaptureViews.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CaptureViews.swift; sourceTree = "<group>"; }};
		{I['fr_wintents']} /* CaptureIntents.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CaptureIntents.swift; sourceTree = "<group>"; }};
		{I['fr_wassets']} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};
		{I['fr_went']} /* SAVYWatch.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = SAVYWatch.entitlements; sourceTree = "<group>"; }};
		{I['fr_wwswift']} /* SAVYWatchWidgets.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SAVYWatchWidgets.swift; sourceTree = "<group>"; }};
		{I['fr_wwinfo']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
		{I['prod_watch']} /* SAVYWatch.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SAVYWatch.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['prod_widgets']} /* SAVYWatchWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = SAVYWatchWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
"""
insert_before("/* End PBXFileReference section */", fr)

# --- PBXFrameworksBuildPhase
fw = f"""		{I['w_frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['ww_frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""
insert_before("/* End PBXFrameworksBuildPhase section */", fw)

# --- Groups: add files to SAVY group, new groups, main group, products
old = "				72CDA1CA00DAA63B15761979 /* StoryFormView.swift */,\n				91ECB28D206394A46BDB0729 /* Fonts */,"
assert s.count(old) == 1
s = s.replace(old, "				72CDA1CA00DAA63B15761979 /* StoryFormView.swift */,\n"
              f"				{I['fr_capture']} /* WatchCapture.swift */,\n"
              f"				{I['fr_importer']} /* WatchCaptureImporter.swift */,\n"
              "				91ECB28D206394A46BDB0729 /* Fonts */,")

old = "				B04A7A0C7EE66517EEA3C9AB /* SAVYUITests */,\n				2B1FBB9014C427ADF4F73315 /* Products */,"
assert s.count(old) == 1
s = s.replace(old, "				B04A7A0C7EE66517EEA3C9AB /* SAVYUITests */,\n"
              f"				{I['g_watch']} /* SAVYWatch */,\n"
              f"				{I['g_widgets']} /* SAVYWatchWidgets */,\n"
              "				2B1FBB9014C427ADF4F73315 /* Products */,")

old = "				5503A99385004788C0010715 /* SAVYUITests.xctest */,\n			);\n			name = Products;"
assert s.count(old) == 1
s = s.replace(old, "				5503A99385004788C0010715 /* SAVYUITests.xctest */,\n"
              f"				{I['prod_watch']} /* SAVYWatch.app */,\n"
              f"				{I['prod_widgets']} /* SAVYWatchWidgets.appex */,\n"
              "			);\n			name = Products;")

groups = f"""		{I['g_watch']} /* SAVYWatch */ = {{
			isa = PBXGroup;
			children = (
				{I['fr_wassets']} /* Assets.xcassets */,
				{I['fr_wintents']} /* CaptureIntents.swift */,
				{I['fr_wviews']} /* CaptureViews.swift */,
				{I['fr_went']} /* SAVYWatch.entitlements */,
				{I['fr_wapp']} /* SAVYWatchApp.swift */,
				{I['fr_wstore']} /* WatchCaptureStore.swift */,
			);
			path = SAVYWatch;
			sourceTree = "<group>";
		}};
		{I['g_widgets']} /* SAVYWatchWidgets */ = {{
			isa = PBXGroup;
			children = (
				{I['fr_wwinfo']} /* Info.plist */,
				{I['fr_wwswift']} /* SAVYWatchWidgets.swift */,
			);
			path = SAVYWatchWidgets;
			sourceTree = "<group>";
		}};
"""
insert_before("/* End PBXGroup section */", groups)

# --- Native targets
targets = f"""		{I['t_watch']} /* SAVYWatch */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['cl_watch']} /* Build configuration list for PBXNativeTarget "SAVYWatch" */;
			buildPhases = (
				{I['w_sources']} /* Sources */,
				{I['w_frameworks']} /* Frameworks */,
				{I['w_resources']} /* Resources */,
				{I['w_embed']} /* Embed Foundation Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				{I['dep_widgets']} /* PBXTargetDependency */,
			);
			name = SAVYWatch;
			packageProductDependencies = (
			);
			productName = SAVYWatch;
			productReference = {I['prod_watch']} /* SAVYWatch.app */;
			productType = "com.apple.product-type.application";
		}};
		{I['t_widgets']} /* SAVYWatchWidgets */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['cl_widgets']} /* Build configuration list for PBXNativeTarget "SAVYWatchWidgets" */;
			buildPhases = (
				{I['ww_sources']} /* Sources */,
				{I['ww_frameworks']} /* Frameworks */,
				{I['ww_resources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = SAVYWatchWidgets;
			packageProductDependencies = (
			);
			productName = SAVYWatchWidgets;
			productReference = {I['prod_widgets']} /* SAVYWatchWidgets.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
"""
insert_before("/* End PBXNativeTarget section */", targets)

# --- Project attributes + targets list
old = """					F9770833D9C90E9EA5883D75 = {
						DevelopmentTeam = 7FKUS5M5QS;
						ProvisioningStyle = Automatic;
					};
				};"""
assert s.count(old) == 1
s = s.replace(old, f"""					F9770833D9C90E9EA5883D75 = {{
						DevelopmentTeam = 7FKUS5M5QS;
						ProvisioningStyle = Automatic;
					}};
					{I['t_watch']} = {{
						DevelopmentTeam = 7FKUS5M5QS;
						ProvisioningStyle = Automatic;
					}};
					{I['t_widgets']} = {{
						DevelopmentTeam = 7FKUS5M5QS;
						ProvisioningStyle = Automatic;
					}};
				}};""")
old = "				C786FF3174742FDC23101F57 /* SAVYUITests */,\n			);\n		};\n/* End PBXProject section */"
assert s.count(old) == 1
s = s.replace(old, "				C786FF3174742FDC23101F57 /* SAVYUITests */,\n"
              f"				{I['t_watch']} /* SAVYWatch */,\n"
              f"				{I['t_widgets']} /* SAVYWatchWidgets */,\n"
              "			);\n		};\n/* End PBXProject section */")

# --- Resources phases
res = f"""		{I['w_resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['bf_w_assets']} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['ww_resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""
insert_before("/* End PBXResourcesBuildPhase section */", res)

# --- Sources phases: add to iOS app sources + new
old = "		D55E3BE5696C587E1340EAAF /* Sources */ = {\n			isa = PBXSourcesBuildPhase;\n			buildActionMask = 2147483647;\n			files = (\n"
assert s.count(old) == 1
s = s.replace(old, old + f"				{I['bf_ios_capture']} /* WatchCapture.swift in Sources */,\n"
                         f"				{I['bf_ios_importer']} /* WatchCaptureImporter.swift in Sources */,\n")
src = f"""		{I['w_sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['bf_w_intents']} /* CaptureIntents.swift in Sources */,
				{I['bf_w_views']} /* CaptureViews.swift in Sources */,
				{I['bf_w_app']} /* SAVYWatchApp.swift in Sources */,
				{I['bf_w_capture']} /* WatchCapture.swift in Sources */,
				{I['bf_w_store']} /* WatchCaptureStore.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['ww_sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['bf_ww_swift']} /* SAVYWatchWidgets.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""
insert_before("/* End PBXSourcesBuildPhase section */", src)

# --- Target dependency
dep = f"""		{I['dep_widgets']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {I['t_widgets']} /* SAVYWatchWidgets */;
			targetProxy = {I['proxy_widgets']} /* PBXContainerItemProxy */;
		}};
"""
insert_before("/* End PBXTargetDependency section */", dep)

# --- Build configurations
def watch_cfg(cid, name):
    return f"""		{cid} /* {name} */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = SAVYWatch/SAVYWatch.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = 7FKUS5M5QS;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleDisplayName = SAVY;
				INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown";
				INFOPLIST_KEY_WKCompanionAppBundleIdentifier = com.adamblair.savy;
				INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = YES;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.adamblair.savy.watchkitapp;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = watchos;
				SWIFT_EMIT_LOC_STRINGS = YES;
				TARGETED_DEVICE_FAMILY = 4;
				WATCHOS_DEPLOYMENT_TARGET = 11.0;
			}};
			name = {name};
		}};
"""
def widget_cfg(cid, name):
    return f"""		{cid} /* {name} */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				APPLICATION_EXTENSION_API_ONLY = YES;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = 7FKUS5M5QS;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = SAVYWatchWidgets/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = SAVY;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.adamblair.savy.watchkitapp.widgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = watchos;
				SKIP_INSTALL = YES;
				SWIFT_EMIT_LOC_STRINGS = YES;
				TARGETED_DEVICE_FAMILY = 4;
				WATCHOS_DEPLOYMENT_TARGET = 11.0;
			}};
			name = {name};
		}};
"""
cfgs = (watch_cfg(I['c_watch_debug'], "Debug") + watch_cfg(I['c_watch_release'], "Release")
        + widget_cfg(I['c_widgets_debug'], "Debug") + widget_cfg(I['c_widgets_release'], "Release"))
insert_before("/* End XCBuildConfiguration section */", cfgs)

lists = f"""		{I['cl_watch']} /* Build configuration list for PBXNativeTarget "SAVYWatch" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['c_watch_debug']} /* Debug */,
				{I['c_watch_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		}};
		{I['cl_widgets']} /* Build configuration list for PBXNativeTarget "SAVYWatchWidgets" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['c_widgets_debug']} /* Debug */,
				{I['c_widgets_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		}};
"""
insert_before("/* End XCConfigurationList section */", lists)

open(path, "w").write(s)
print("watch target", I['t_watch'], "widgets target", I['t_widgets'], "watch product", I['prod_watch'])
