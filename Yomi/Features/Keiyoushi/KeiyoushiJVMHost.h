#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Hosts one OpenJDK Mobile (Zero interpreter) VM inside Yomi and starts M-Extension-Server's EmbeddedBridge on
/// 127.0.0.1, so Keiyoushi (Mihon) extensions run on the device with no server. See Yomi/KEIYOUSHI_POC.md.
///
/// The runtime framework is loaded with dlopen, never linked: OpenJDK Mobile has no simulator slice, and only
/// device builds that opt in (Config/Personal.xcconfig) embed it. `isAvailable` is false everywhere else.
/// One VM per process, ever — it lives on a dedicated thread with a large native stack (Zero keeps its Java frames
/// there) and every JNI call is marshalled onto that thread.
@interface KeiyoushiJVMHost : NSObject
@property (class, readonly) KeiyoushiJVMHost *shared;
/// True when this build embeds the runtime (device + personal build).
@property (class, readonly) BOOL isAvailable;
/// Creates the VM on first use, then (re)starts the bridge; an already-running bridge just returns its port.
/// `token` locks the bridge: every request must send it as `X-Yomi-Bridge-Token` (S191). Pass the same token on
/// every start in one process. A runtime too old to take a token fails to start instead of serving unlocked.
/// Completion runs on the main queue with port 0 and an error message on failure.
- (void)startWithToken:(NSString *)token completion:(void (^)(NSInteger port, NSString *_Nullable error))completion;
/// Stops serving but keeps loaded extensions (the app is going to the background).
- (void)pauseBridge;

// MARK: Direct JNI transport (A6) — no loopback server, no port, no token.

/// Creates the VM on first use and prepares the extension runtime (`mextensionserver.YomiHost.start`).
/// `apkDirectory` is the only folder `apkPath` requests may read from. Safe to call again (cheap after the first).
/// Completion runs on a background queue; error is nil on success.
- (void)startEngineWithAPKDirectory:(NSString *)apkDirectory
                         completion:(void (^)(NSString *_Nullable error))completion;
/// One `/dalvik`-shaped request (UTF-8 JSON). Completion runs on a background queue with an HTTP-style status,
/// the UTF-8 JSON answer, and the server-issued extension handle on success.
- (void)callWithRequest:(NSData *)json
              userAgent:(NSString *)userAgent
                cookies:(nullable NSString *)cookies
             completion:(void (^)(NSInteger status, NSData *body, NSString *_Nullable extensionId))completion;
/// The image behind `keiyoushi-image://<imageId>`. Completion runs on a background queue.
- (void)imageWithId:(NSString *)imageId
         completion:(void (^)(NSInteger status, NSString *_Nullable contentType, NSData *_Nullable bytes))completion;
@end

NS_ASSUME_NONNULL_END
