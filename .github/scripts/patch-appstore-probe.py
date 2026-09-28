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
    "*mainBundleAddr = (void *)CFBundleGetMainBundle();",
)
bootstrap.write_text(text)

# Remove the private UIScene swizzle registration; the TestFlight flavor uses the public scene API.
app_delegate = Path("LiveContainerSwiftUI/App/AppDelegate.swift")
text = app_delegate.read_text()
swizzle_block = """        // allow new scene pop up as a new fullscreen window
        method_exchangeImplementations(
            class_getInstanceMethod(UIApplication.self, #selector(UIApplication.requestSceneSessionActivation(_ :userActivity:options:errorHandler:)))!,
            class_getInstanceMethod(UIApplication.self, #selector(UIApplication.hook_requestSceneSessionActivation(_:userActivity:options:errorHandler:)))!)

"""
text = text.replace(swizzle_block, "")
app_delegate.write_text(text)

# Remove the private UIScene fullscreen request option; public activation still works.
app_delegate = Path("LiveContainerSwiftUI/App/AppDelegate.swift")
text = app_delegate.read_text()
text = text.replace(
    "        newOptions!._setRequestFullscreen(UIScreen.main.bounds == self.keyWindow!.bounds)\n",
    "",
)
app_delegate.write_text(text)

# Disable the optional cloned-IPA exporter in the TestFlight flavor.
# Upstream implements ZIP creation through private PassKitCore PKZipArchiver.
lcutils_h = Path("LiveContainerSwiftUI/Utilities/LCUtils.h")
text = lcutils_h.read_text()
text = re.sub(
    r'\n@interface PKZipArchiver : NSObject\n\n- \(NSData \*\)zippedDataForURL:\(NSURL \*\)url;\n\n@end\n',
    '\n',
    text,
    count=1,
)
lcutils_h.write_text(text)

# Replace private PassKitCore PKZipArchiver with the project's bundled libarchive.
lcutils = Path("LiveContainerSwiftUI/Utilities/LCUtils.m")
text = lcutils.read_text()
if '#include "archive.h"' not in text:
    text = text.replace(
        '#import "LiveContainerSwiftUI-Swift.h"\n',
        '#import "LiveContainerSwiftUI-Swift.h"\n#include "archive.h"\n#include "archive_entry.h"\n',
        1,
    )

zip_helper = r'''
static NSError *LCZipError(struct archive *archive, NSString *operation) {
    const char *message = archive ? archive_error_string(archive) : NULL;
    NSString *description = message ? [NSString stringWithUTF8String:message] : @"ZIP operation failed";
    return [NSError errorWithDomain:@"LiveContainer.AppStoreZip"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey:
                                          [NSString stringWithFormat:@"%@: %@", operation, description]}];
}

static BOOL LCZipDirectoryToFile(NSURL *rootURL, NSURL *zipURL, NSError **error) {
    struct archive *writer = archive_write_new();
    if (!writer) {
        if (error) *error = [NSError errorWithDomain:@"LiveContainer.AppStoreZip"
                                                code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"Unable to create ZIP writer"}];
        return NO;
    }

    if (archive_write_set_format_zip(writer) != ARCHIVE_OK ||
        archive_write_zip_set_compression_deflate(writer) != ARCHIVE_OK ||
        archive_write_open_filename(writer, zipURL.fileSystemRepresentation) != ARCHIVE_OK) {
        if (error) *error = LCZipError(writer, @"Opening ZIP");
        archive_write_free(writer);
        return NO;
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSURLResourceKey> *keys = @[
        NSURLIsDirectoryKey,
        NSURLIsSymbolicLinkKey,
        NSURLFileSizeKey,
        NSURLFileResourceIdentifierKey
    ];

    NSDirectoryEnumerator<NSURL *> *enumerator =
        [fm enumeratorAtURL:rootURL
 includingPropertiesForKeys:keys
                    options:0
               errorHandler:^BOOL(NSURL *url, NSError *enumerationError) {
        if (error && !*error) *error = enumerationError;
        return NO;
    }];

    for (NSURL *itemURL in enumerator) {
        if (error && *error) {
            archive_write_close(writer);
            archive_write_free(writer);
            return NO;
        }

        NSString *rootPath = rootURL.path;
        NSString *itemPath = itemURL.path;
        if (![itemPath hasPrefix:rootPath]) continue;

        NSString *relativePath = [itemPath substringFromIndex:rootPath.length];
        if ([relativePath hasPrefix:@"/"]) {
            relativePath = [relativePath substringFromIndex:1];
        }
        if (relativePath.length == 0) continue;

        NSNumber *isDirectory = nil;
        NSNumber *isSymbolicLink = nil;
        NSNumber *fileSize = nil;
        [itemURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        [itemURL getResourceValue:&isSymbolicLink forKey:NSURLIsSymbolicLinkKey error:nil];
        [itemURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];

        struct archive_entry *entry = archive_entry_new();
        if (!entry) {
            if (error) *error = [NSError errorWithDomain:@"LiveContainer.AppStoreZip"
                                                    code:3
                                                userInfo:@{NSLocalizedDescriptionKey: @"Unable to create ZIP entry"}];
            archive_write_close(writer);
            archive_write_free(writer);
            return NO;
        }

        NSString *entryPath = relativePath;
        if (isDirectory.boolValue && ![entryPath hasSuffix:@"/"]) {
            entryPath = [entryPath stringByAppendingString:@"/"];
        }
        archive_entry_set_pathname(entry, entryPath.fileSystemRepresentation);

        if (isSymbolicLink.boolValue) {
            NSError *linkError = nil;
            NSString *target = [fm destinationOfSymbolicLinkAtPath:itemPath error:&linkError];
            if (!target) {
                if (error) *error = linkError;
                archive_entry_free(entry);
                archive_write_close(writer);
                archive_write_free(writer);
                return NO;
            }
            archive_entry_set_filetype(entry, AE_IFLNK);
            archive_entry_set_perm(entry, 0777);
            archive_entry_set_size(entry, 0);
            archive_entry_set_symlink(entry, target.fileSystemRepresentation);
        } else if (isDirectory.boolValue) {
            archive_entry_set_filetype(entry, AE_IFDIR);
            archive_entry_set_perm(entry, 0755);
            archive_entry_set_size(entry, 0);
        } else {
            archive_entry_set_filetype(entry, AE_IFREG);
            archive_entry_set_perm(entry, 0644);
            archive_entry_set_size(entry, fileSize.longLongValue);
        }

        if (archive_write_header(writer, entry) != ARCHIVE_OK) {
            if (error) *error = LCZipError(writer, @"Writing ZIP header");
            archive_entry_free(entry);
            archive_write_close(writer);
            archive_write_free(writer);
            return NO;
        }

        if (!isDirectory.boolValue && !isSymbolicLink.boolValue) {
            NSError *readError = nil;
            NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:itemURL error:&readError];
            if (!handle) {
                if (error) *error = readError;
                archive_entry_free(entry);
                archive_write_close(writer);
                archive_write_free(writer);
                return NO;
            }

            while (YES) {
                @autoreleasepool {
                    NSData *chunk = [handle readDataOfLength:64 * 1024];
                    if (chunk.length == 0) break;
                    if (archive_write_data(writer, chunk.bytes, chunk.length) < 0) {
                        if (error) *error = LCZipError(writer, @"Writing ZIP data");
                        [handle closeFile];
                        archive_entry_free(entry);
                        archive_write_close(writer);
                        archive_write_free(writer);
                        return NO;
                    }
                }
            }
            [handle closeFile];
        }

        archive_entry_free(entry);
    }

    if (archive_write_close(writer) != ARCHIVE_OK) {
        if (error) *error = LCZipError(writer, @"Closing ZIP");
        archive_write_free(writer);
        return NO;
    }
    archive_write_free(writer);
    return YES;
}

'''
if "static BOOL LCZipDirectoryToFile" not in text:
    text = text.replace("@implementation LCUtils\n", zip_helper + "\n@implementation LCUtils\n", 1)

old_zip = r'''    [infoDict writeToURL:infoPath error:error];
    
    dlopen("/System/Library/PrivateFrameworks/PassKitCore.framework/PassKitCore", RTLD_GLOBAL);
    NSData *zipData = [[NSClassFromString(@"PKZipArchiver") new] zippedDataForURL:tmpPayloadPath.URLByDeletingLastPathComponent];
    if (!zipData) return nil;

    [manager removeItemAtURL:tmpPayloadPath error:error];
    if (*error) return nil;
    
    if([manager fileExistsAtPath:tmpIPAPath.path]) {
        [manager removeItemAtURL:tmpIPAPath error:error];
        if (*error) return nil;
    }

    [zipData writeToURL:tmpIPAPath options:0 error:error];
    if (*error) return nil;

    return tmpIPAPath;
'''
new_zip = r'''    [infoDict writeToURL:infoPath error:error];
    if (*error) return nil;

    if ([manager fileExistsAtPath:tmpIPAPath.path]) {
        [manager removeItemAtURL:tmpIPAPath error:error];
        if (*error) return nil;
    }

    NSURL *archiveRoot = tmpPayloadPath.URLByDeletingLastPathComponent;
    if (!LCZipDirectoryToFile(archiveRoot, tmpIPAPath, error)) {
        return nil;
    }

    [manager removeItemAtURL:archiveRoot error:nil];
    return tmpIPAPath;
'''
if old_zip not in text:
    raise SystemExit("private PKZipArchiver block was not found")
text = text.replace(old_zip, new_zip, 1)
lcutils.write_text(text)

# Remove the private archiver declaration so the selector is absent from compiled metadata too.
lcutils_h = Path("LiveContainerSwiftUI/Utilities/LCUtils.h")
text = lcutils_h.read_text()
text = re.sub(
    r'\n@interface PKZipArchiver : NSObject\s*- \(NSData \*\)zippedDataForURL:\(NSURL \*\)url;\s*@end\s*',
    '\n',
    text,
    count=1,
    flags=re.S,
)
lcutils_h.write_text(text)

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
    "zippedDataForURL:": [Path("LiveContainerSwiftUI")],
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


# The fullscreen scene-activation hook uses private UIKit behavior. Remove both
# the swizzle installation and its replacement method in the TestFlight flavor.
app_delegate = Path("LiveContainerSwiftUI/App/AppDelegate.swift")
app_text = app_delegate.read_text()
app_text = re.sub(
    r'\n\s*// allow new scene pop up as a new fullscreen window\n\s*method_exchangeImplementations\(.*?\n\s*\)\n',
    '\n',
    app_text,
    count=1,
    flags=re.S,
)
app_text, n = re.subn(
    r'\n@objc extension UIApplication \{.*?\n\}\n\npublic class ViewAppIntentHandler',
    '\npublic class ViewAppIntentHandler',
    app_text,
    count=1,
    flags=re.S,
)
if n != 1:
    raise SystemExit("failed to remove private UIApplication scene-activation extension")
app_delegate.write_text(app_text)

print("TestFlight public-API flavor patch applied")
