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
@end

NS_ASSUME_NONNULL_END
