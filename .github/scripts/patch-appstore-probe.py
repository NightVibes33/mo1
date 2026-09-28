from pathlib import Path

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
    Path("MultitaskSupport/UIKitPrivate+MultitaskSupport.h"): [
        "#define UIApp UIApplication.sharedApplication",
    ],
}

for path, needles in checks.items():
    text = path.read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"missing App Store compatibility shim {needle!r} in {path}")

shared = Path("LiveContainerSwiftUI/Utilities/Shared.swift").read_text()
if "dyld_get_program_sdk_version()" in shared:
    raise SystemExit("private dyld program SDK call remains in Shared.swift")

tab = Path("LiveContainerSwiftUI/Views/LCTabView.swift").read_text()
if "SecTaskCreateFromSelf" in tab or "SecTaskCopyValueForEntitlement" in tab:
    raise SystemExit("private SecTask Swift call remains in LCTabView.swift")

print("App Store compatibility source shims verified")
