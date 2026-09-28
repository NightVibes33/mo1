from pathlib import Path
import re

root = Path(".")

# Replace direct Security private entitlement lookups with a local compatibility shim.
for base in (Path("LiveContainer"), Path("LiveContainerSwiftUI")):
    for path in base.rglob("*"):
        if path.suffix not in {".m", ".mm", ".h", ".swift"}:
            continue
        text = path.read_text(errors="surrogateescape")
        new = text.replace("SecTaskCreateFromSelf", "LCAppStoreTaskCreate")
        new = new.replace("SecTaskCopyValueForEntitlement", "LCAppStoreTaskCopyValueForEntitlement")
        if new != text:
            path.write_text(new, errors="surrogateescape")

foundation = Path("LiveContainer/FoundationPrivate.h")
text = foundation.read_text()
if "LCAppStoreTaskCreate" not in text:
    raise SystemExit("Security shim declarations were not renamed")
foundation.write_text(text)

shared = Path("LiveContainer/LCSharedUtils.m")
text = shared.read_text()
marker = "@implementation LCSharedUtils"
shim = r'''
void* LCAppStoreTaskCreate(CFAllocatorRef allocator) {
    (void)allocator;
    return (void*)CFRetain(CFSTR("LCAppStoreTask"));
}

CFTypeRef LCAppStoreTaskCopyValueForEntitlement(void *task, CFStringRef key, CFErrorRef *error) {
    (void)task;
    if (error) *error = NULL;
    NSString *name = (__bridge NSString *)key;
    if ([name isEqualToString:@"get-task-allow"]) {
        return CFRetain(kCFBooleanFalse);
    }
    if ([name isEqualToString:@"com.apple.security.application-groups"]) {
        return CFBridgingRetain(@[]);
    }
    if ([name isEqualToString:@"application-identifier"]) {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"com.nightvibes.prism.39A8Q3T3TR";
        NSString *team = [LCSharedUtils teamIdentifier];
        NSString *identifier = team.length ? [NSString stringWithFormat:@"%@.%@", team, bundle] : bundle;
        return CFBridgingRetain(identifier);
    }
    // Let LCSharedUtils.teamIdentifier fall through to the public Keychain access-group path.
    return NULL;
}

'''
if shim.strip() not in text:
    text = text.replace(marker, shim + marker, 1)
shared.write_text(text)

# Remove direct CoreFoundation process-global private symbol imports. For the App Store
# flavor these become process-local shadows; guest launch paths can still be exercised
# without importing Apple's private symbols.
utils_h = Path("LiveContainer/utils.h")
text = utils_h.read_text()
text = text.replace("const char **_CFGetProgname(void);", "static inline const char **LCAppStoreGetProgname(void) { static const char *value = NULL; return &value; }")
text = text.replace("const char **_CFGetProcessPath(void);", "static inline const char **LCAppStoreGetProcessPath(void) { static const char *value = NULL; return &value; }")
utils_h.write_text(text)

for path in Path("LiveContainer").rglob("*"):
    if path.suffix not in {".m", ".mm", ".h"}:
        continue
    text = path.read_text(errors="surrogateescape")
    new = text.replace("_CFGetProgname()", "LCAppStoreGetProgname()")
    new = new.replace("_CFGetProcessPath()", "LCAppStoreGetProcessPath()")
    if new != text:
        path.write_text(new, errors="surrogateescape")

# Replace the private UIKit UIApp global with the public UIApplication singleton.
multi_h = Path("MultitaskSupport/UIKitPrivate+MultitaskSupport.h")
text = multi_h.read_text()
text = text.replace("extern const UIApplication *UIApp;", "#define UIApp UIApplication.sharedApplication")
multi_h.write_text(text)

# Replace private dyld SDK helpers with local public compatibility helpers.
lcutils_h = Path("LiveContainerSwiftUI/Utilities/LCUtils.h")
text = lcutils_h.read_text()
anchor = "void refreshFile(NSString* execPath);"
decls = """void refreshFile(NSString* execPath);
uint32_t LCAppStoreProgramSDKVersion(void);
uint32_t LCAppStoreSDKVersion(const struct mach_header* mh);"""
if anchor in text:
    text = text.replace(anchor, decls, 1)
else:
    raise SystemExit("LCUtils.h insertion anchor missing")
lcutils_h.write_text(text)

lcutils_m = Path("LiveContainerSwiftUI/Utilities/LCUtils.m")
text = lcutils_m.read_text()
impl_anchor = "@implementation LCUtils"
impl = r'''
uint32_t LCAppStoreProgramSDKVersion(void) {
    // Xcode 26 / iOS 26 App Store flavor. This value is only used for UI compatibility gating.
    return 0x001A0000;
}

uint32_t LCAppStoreSDKVersion(const struct mach_header* mh) {
    if (!mh) return 0x000B0000;
    const uint8_t *cursor = (const uint8_t *)mh + ((mh->magic == MH_MAGIC_64 || mh->magic == MH_CIGAM_64) ? sizeof(struct mach_header_64) : sizeof(struct mach_header));
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmd == LC_BUILD_VERSION && lc->cmdsize >= sizeof(struct build_version_command)) {
            const struct build_version_command *bv = (const struct build_version_command *)lc;
            return bv->sdk;
        }
        if (lc->cmd == LC_VERSION_MIN_IPHONEOS && lc->cmdsize >= sizeof(struct version_min_command)) {
            const struct version_min_command *vm = (const struct version_min_command *)lc;
            return vm->sdk;
        }
        if (lc->cmdsize < sizeof(struct load_command)) break;
        cursor += lc->cmdsize;
    }
    return 0x000B0000;
}

'''
if impl.strip() not in text:
    text = text.replace(impl_anchor, impl + impl_anchor, 1)
lcutils_m.write_text(text)

for path in Path("LiveContainerSwiftUI").rglob("*"):
    if path.suffix not in {".m", ".mm", ".h", ".swift"}:
        continue
    text = path.read_text(errors="surrogateescape")
    new = text.replace("dyld_get_program_sdk_version()", "LCAppStoreProgramSDKVersion()")
    new = new.replace("dyld_get_sdk_version(", "LCAppStoreSDKVersion(")
    if new != text:
        path.write_text(new, errors="surrogateescape")

# Sanity checks: the App Store-shipped core must not retain direct imports of these names.
for needle in (
    "SecTaskCreateFromSelf",
    "SecTaskCopyValueForEntitlement",
    "_CFGetProcessPath()",
    "_CFGetProgname()",
    "dyld_get_program_sdk_version()",
    "dyld_get_sdk_version(",
):
    matches = []
    for base in (Path("LiveContainer"), Path("LiveContainerSwiftUI")):
        for path in base.rglob("*"):
            if path.suffix in {".m", ".mm", ".h", ".swift"}:
                if needle in path.read_text(errors="surrogateescape"):
                    matches.append(str(path))
    if matches:
        raise SystemExit(f"private symbol source reference remains for {needle}: {matches}")

print("App Store public-API compatibility source patch applied")
