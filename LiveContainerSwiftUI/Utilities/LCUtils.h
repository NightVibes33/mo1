#import <Foundation/Foundation.h>
#import "LCMachOUtils.h"
#import "utils.h"
@import UIKit;

typedef NS_ENUM(NSInteger, Store){
    SideStore = 0,
    AltStore = 1,
    ADP = 2,
    Unknown = -1
};

void refreshFile(NSString* execPath);

static inline uint32_t LCAppStoreSDKVersion(const struct mach_header* mh) {
    if (!mh) return 0;
    const uint8_t *cursor = (const uint8_t *)mh;
    uint32_t ncmds = mh->ncmds;
    if (mh->magic == MH_MAGIC_64 || mh->magic == MH_CIGAM_64) {
        cursor += sizeof(struct mach_header_64);
    } else {
        cursor += sizeof(struct mach_header);
    }
    for (uint32_t i = 0; i < ncmds; ++i) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmd == LC_BUILD_VERSION && lc->cmdsize >= sizeof(struct build_version_command)) {
            return ((const struct build_version_command *)lc)->sdk;
        }
        if (lc->cmd == LC_VERSION_MIN_IPHONEOS && lc->cmdsize >= sizeof(struct version_min_command)) {
            return ((const struct version_min_command *)lc)->sdk;
        }
        if (lc->cmdsize < sizeof(struct load_command)) break;
        cursor += lc->cmdsize;
    }
    return 0x000B0000;
}

#define dyld_get_sdk_version LCAppStoreSDKVersion

@interface PKZipArchiver : NSObject

- (NSData *)zippedDataForURL:(NSURL *)url;

@end

@interface UIDevice(private)
@property(readonly) NSString* buildVersion;
@end

@interface LCUtils : NSObject

+ (void)validateJITLessSetupWithCompletionHandler:(void (^)(BOOL success, NSError *error))completionHandler;
+ (NSURL *)archiveIPAWithBundleName:(NSString*)newBundleName includingExtraInfoDict:(NSDictionary *)extraInfoDict error:(NSError **)error;
+ (NSData *)certificateData;
+ (void)launchMultitaskGuestApp:(NSString *)displayName completionHandler:(void (^)(NSNumber *pid, NSError *error))completionHandler API_AVAILABLE(ios(16.0));


+ (NSProgress *)signAppBundleWithZSign:(NSURL *)path completionHandler:(void (^)(BOOL success, NSError *error))completionHandler;
+ (NSProgress *)signFilesWithZSignWithURLs:(NSArray<NSURL*>*)urls completionHandler:(void (^)(BOOL success, NSError *error))completionHandler;
+ (NSString*)getCertTeamIdWithKeyData:(NSData*)keyData password:(NSString*)password;
+ (int)validateCertificateWithCompletionHandler:(void(^)(int status, NSDate *expirationDate, NSString *organizationalUnitName, NSString *error))completionHandler;

+ (BOOL)isTXMScriptRequired;
+ (NSString *)base64EncodedUniversalJITScript;

+ (BOOL)isAppGroupAltStoreLike;
+ (Store)store;
+ (NSString *)appUrlScheme;
+ (NSString *)storeInstallURLScheme;
+ (NSString *)getVersionInfo;
+ (NSString *)liveProcessBundleIdentifier;
+ (NSData*)bookmarkForURL:(NSURL*) url;
@end

@interface NSUserDefaults(LiveContainer)
+ (bool)sideStoreExist;
@end

@interface LCP12CertHelper : NSObject

- (instancetype)initWithP12Data:(NSData*)p12Data password:(NSString*)password error:(NSError**)error;
- (NSDate*)getNotValidityNotAfterWithError:(NSError**)error;
- (NSString*)getOrgnizationUnitWithError:(NSError**)error;

@end

typedef NS_ENUM(NSInteger, GeneratedIconStyle){
    Original = -1,
    Light = 0,
    Dark = 1
};

@interface UIImage(LiveContainer)
+ (instancetype)generateIconForBundleURL:(NSURL*)url style:(GeneratedIconStyle)style hasBorder:(BOOL)hasBorder;
@end
BOOL saveCGImage(CGImageRef image, NSURL *url);
CGImageRef loadCGImageFromURL(NSURL *url);
NSNumber *LCGetDefaultClassicMode(NSURL *appURL);
