from pathlib import Path
import re

def replace_exact(path: Path, old: str, new: str, label: str):
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"missing expected source for {label}: {path}")
    path.write_text(text.replace(old, new, 1))

# Verify the source-level App Store compatibility shims that are committed on this temp branch.
checks = {
    Path("LiveContainer/FoundationPrivate.h"): [
        "LCAppStoreTaskCreateFromSelf",
        "LCAppStoreTaskCopyValueForEntitlement",
    ],
    Path("LiveContainer/utils.h"): [
        "LCAppStoreGetProgname",
        "LCAppStoreGetProcessPath",
    ],
    Path("LiveContainerSwiftUI/Utilities/LCUtils.h"): [
        "LCAppStoreSDKVersion",
    ],
}
for path, needles in checks.items():
    text = path.read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"missing App Store compatibility shim {needle!r} in {path}")

# ---- Disable private multitask scene hosting in the TestFlight flavor only. ----
# Keep the public enum/API surface so existing SwiftUI call sites compile, but all
# multitask operations return unavailable/false.
mt = Path("MultitaskSupport")
for path in mt.iterdir():
    if path.name == "MultitaskManager.swift":
        continue
    if path.suffix in {".m", ".mm"}:
        path.write_text("#import <Foundation/Foundation.h>\n")
    elif path.suffix == ".h":
        path.write_text("#import <Foundation/Foundation.h>\n")
    elif path.suffix == ".swift":
        path.write_text("// Multitask private scene-hosting implementation disabled for TestFlight.\n")

Path("MultitaskSupport/MultitaskManager.swift").write_text(r'''import Foundation
import SwiftUI

@objc enum MultitaskMode: Int {
    case virtualWindow = 0
    case nativeWindow = 1
}

@objc class MultitaskManager: NSObject {
    @objc class func registerMultitaskContainer(container: String) {}
    @objc class func unregisterMultitaskContainer(container: String) {}
    @objc class func isUsing(container: String) -> Bool { false }
    @objc class func isMultitasking() -> Bool { false }
}

@available(iOS 16.1, *)
@objc class MultitaskWindowManager: NSObject {
    @objc class func openExistingAppWindow(dataUUID: String) -> Bool { false }
}

@available(iOS 16.0, *)
@objc public class MultitaskDockManager: NSObject {
    @objc public static let shared = MultitaskDockManager()
    @objc public func bringMultitaskViewToFront(uuid: String) -> Bool { false }
}

@available(iOS 16.1, *)
struct MultitaskAppWindow: View {
    let id: String
    var body: some View {
        Text("Multitasking is unavailable in this TestFlight build.")
    }
}
''')

# Remove private multitask Objective-C references from LCUtils while preserving
# the method signature used by Swift concurrency bridging.
lcutils = Path("LiveContainerSwiftUI/Utilities/LCUtils.m")
text = lcutils.read_text()
text = text.replace('#import "../../MultitaskSupport/DecoratedAppSceneViewController.h"\n', '')
start = text.find("#pragma mark Multitasking")
end = text.find("#pragma mark Code signing")
if start < 0 or end < 0 or end <= start:
    raise SystemExit("unable to locate LCUtils multitasking section")
text = text[:start] + r'''#pragma mark Multitasking
+ (NSString *)liveProcessBundleIdentifier {
    return nil;
}

+ (void)launchMultitaskGuestApp:(NSString *)displayName completionHandler:(void (^)(NSNumber *pid, NSError *error))completionHandler {
    if (completionHandler) {
        NSError *error = [NSError errorWithDomain:(displayName ?: @"LiveContainer")
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"Multitasking is unavailable in this TestFlight build."}];
        completionHandler(nil, error);
    }
}

''' + text[end:]
lcutils.write_text(text)

# TweakLoader itself stays embedded and still loads tweaks. Only the private
# scene/file-picker compatibility categories are removed.
Path("TweakLoader/DocumentPicker.m").write_text("#import <Foundation/Foundation.h>\n")
Path("TweakLoader/UIKit+GuestHooks.m").write_text("#import <Foundation/Foundation.h>\n")

# These linker flags force references to private Objective-C classes even after
# the private hook sources are removed.
pbx = Path("LiveContainer.xcodeproj/project.pbxproj")
text = pbx.read_text()
for flag in (
    '\t\t\t\t\t"-Wl,-U,_OBJC_CLASS_$_FBSSceneParameters",\n',
    '\t\t\t\t\t"-Wl,-U,_OBJC_CLASS_$_LSApplicationWorkspace",\n',
    '\t\t\t\t\t"-Wl,-U,_OBJC_CLASS_$_DOCConfiguration",\n',
):
    text = text.replace(flag, "")
pbx.write_text(text)

# ---- Replace the two private LiveContainerShared selector mechanisms. ----
# Keep the exported initializer used by the host, but use public NSBundle init.
Path("LiveContainer/Tweaks/NSBundle+FixCydiaSubstrate.m").write_text(r'''#import <Foundation/Foundation.h>
#import "Tweaks.h"

@implementation NSString(LiveContainer)
- (NSString *)lc_realpath {
    char result[PATH_MAX];
    if (realpath(self.fileSystemRepresentation, result)) {
        return [NSString stringWithUTF8String:result];
    }
    return self;
}
@end

@implementation NSBundle(LiveContainer)
- (instancetype)initWithPathForMainBundle:(NSString *)path {
    return [self initWithPath:path];
}
@end
''')

# Guest defaults isolation uses private Foundation internals upstream. For the
# TestFlight flavor, guest defaults fall back to the normal process defaults.
Path("LiveContainer/Tweaks/NSUserDefaults.m").write_text(r'''#import <Foundation/Foundation.h>
void NUDGuestHooksInit(void) {}
''')

foundation = Path("LiveContainer/FoundationPrivate.h")
text = foundation.read_text()
text = text.replace("- (id)_cfBundle;\n", "")
text = text.replace("- (void)_setIdentifier:(NSString*)identifier;\n", "")
foundation.write_text(text)

bootstrap = Path("LiveContainer/LCBootstrap.m")
text = bootstrap.read_text()
text = text.replace(
    "*mainBundleAddr = (__bridge void *)NSBundle.mainBundle._cfBundle;",
    "*mainBundleAddr = (__bridge void *)CFBundleGetMainBundle();",
)
bootstrap.write_text(text)

# Sanity checks for the exact App Store validation failures from the prior run.
for needle, roots in {
    "NSExtension": [Path("MultitaskSupport"), Path("LiveContainerSwiftUI/Utilities/LCUtils.m")],
    "UIApplicationSceneSpecification": [Path("MultitaskSupport")],
    "UIApplicationSceneTransitionContext": [Path("MultitaskSupport")],
    "UICustomViewMenuElement": [Path("MultitaskSupport")],
    "UIMutableApplicationSceneSettings": [Path("MultitaskSupport")],
    "UIOpenURLAction": [Path("MultitaskSupport"), Path("TweakLoader")],
    "_UIFluidSliderInteraction": [Path("MultitaskSupport")],
    "_UIPrototypingMenuSlider": [Path("MultitaskSupport")],
    "_UISceneHostingController": [Path("MultitaskSupport")],
    "DOCConfiguration": [Path("TweakLoader")],
    "FBSSceneParameters": [Path("TweakLoader")],
    "._cfBundle": [Path("LiveContainer")],
    "_setIdentifier:": [Path("LiveContainer")],
}.items():
    hits = []
    for root in roots:
        paths = [root] if root.is_file() else list(root.rglob("*"))
        for path in paths:
            if path.is_file() and path.suffix in {".m", ".mm", ".h", ".swift"}:
                if needle in path.read_text(errors="ignore"):
                    hits.append(str(path))
    if hits:
        raise SystemExit(f"private validation token {needle!r} remains in TestFlight sources: {hits}")

print("TestFlight public-API flavor patch applied")
