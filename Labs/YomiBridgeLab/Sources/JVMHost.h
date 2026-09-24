#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Hosts one OpenJDK (Zero) VM inside the app and starts M-Extension-Server's EmbeddedBridge on 127.0.0.1.
/// The VM lives on a dedicated thread with a large native stack (Zero keeps its Java frames there); every JNI call
/// is marshalled onto that thread. One VM per process, ever: it is never destroyed.
@interface JVMHost : NSObject
@property (class, readonly) JVMHost *shared;
/// Creates the VM (first call only) and starts the bridge. Completion runs on the main queue.
/// port is 0 on failure, and error says why. Timings are in milliseconds (createMs is 0 if the VM already existed).
- (void)startWithCompletion:(void (^)(NSInteger port, double createMs, double bridgeMs, NSString *_Nullable error))completion;
/// Stops serving but keeps loaded extensions (call when the app goes to the background).
- (void)pauseBridge;
@end

NS_ASSUME_NONNULL_END
