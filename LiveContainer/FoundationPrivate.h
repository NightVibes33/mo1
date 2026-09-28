#include <Foundation/Foundation.h>

@interface NSBundle(private)
- (id)_cfBundle;
@end

@interface NSUserDefaults(private)
+ (void)setStandardUserDefaults:(id)defaults;
- (instancetype)_initWithSuiteName:(NSString*)suiteName container:(NSURL*)container;
- (void)_setIdentifier:(NSString*)identifier;
- (NSString*)_identifier;
- (NSString*)_container;
- (void)_setContainer:(NSURL*)identifier;
@end

@interface NSExtension : NSObject
@property (nonatomic, strong, readwrite) NSArray *preferredLanguages;
+ (instancetype)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void(^)(NSUUID *))callback;
- (int)pidForRequestIdentifier:(NSUUID *)identifier;
- (void)_kill:(int)arg1;
- (void)setRequestCancellationBlock:(void(^)(NSUUID *uuid, NSError *error))callback;
- (void)setRequestInterruptionBlock:(void(^)(NSUUID *))callback;
- (void)_hostDidEnterBackgroundNote:(NSNotification *)note;
- (void)_hostWillResignActiveNote:(NSNotification *)note;
@end

// App Store/TestFlight-safe entitlement shims for this temporary branch.
// Keep the original source-level API shape while avoiding references to private SecTask symbols.
static inline void *LCAppStoreTaskCreateFromSelf(CFAllocatorRef allocator) {
    (void)allocator;
    return (void *)0x1;
}

static inline CFTypeRef LCAppStoreTaskCopyValueForEntitlement(void *task, CFStringRef key, CFErrorRef *error) {
    (void)task;
    if (error) *error = NULL;
    NSString *keyString = (__bridge NSString *)key;
    if ([keyString isEqualToString:@"application-identifier"]) {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"com.nightvibes.prism.39A8Q3T3TR";
        NSString *value = [@"AAAAAAAAAA." stringByAppendingString:bundleID];
        return CFRetain((__bridge CFTypeRef)value);
    }
    if ([keyString isEqualToString:@"get-task-allow"]) {
        return CFRetain((__bridge CFTypeRef)@NO);
    }
    return NULL;
}

#define SecTaskCreateFromSelf LCAppStoreTaskCreateFromSelf
#define SecTaskCopyValueForEntitlement LCAppStoreTaskCopyValueForEntitlement

NSString *SecTaskCopyTeamIdentifier(void *task, NSError **error);


@interface _CFXPreferences2 : NSObject
+(instancetype)copyDefaultPreferences;
-(CFPropertyListRef)hook_copyAppValueForKey:(CFStringRef)key identifier:(CFStringRef)identifier container:(CFStringRef)container configurationURL:(CFURLRef)configurationURL;
-(CFPropertyListRef)hook_copyValueForKey:(CFStringRef)key identifier:(CFStringRef)identifier user:(CFStringRef)user host:(CFStringRef)host container:(CFStringRef)container;
-(void)hook_setValue:(CFPropertyListRef)value forKey:(CFStringRef)key appIdentifier:(CFStringRef)appIdentifier container:(CFStringRef)container configurationURL:(CFURLRef)configurationURL;
@end

@interface CFPrefsPlistSource2 : NSObject
-(id)hook_initWithDomain:(CFStringRef)arg1 user:(CFStringRef)arg2 byHost:(bool)arg3 containerPath:(CFStringRef)arg4 containingPreferences:(id)arg5 ;
@end

