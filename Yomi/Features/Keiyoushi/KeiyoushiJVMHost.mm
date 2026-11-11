#import "KeiyoushiJVMHost.h"
#include "JNI/jni.h"
#include <dlfcn.h>
#include <atomic>
#include <os/lock.h>
#include <string>
#include <vector>

// Zero runs Java frames on the native stack; the bootstrap needs far more than a dispatch thread's 512 KiB.
static const NSUInteger kJVMThreadStack = 16 * 1024 * 1024;

typedef jint (*CreateJavaVMFn)(JavaVM **, void **, void *);

static NSString *runtimeBinaryPath(void) {
    return [[NSBundle mainBundle].privateFrameworksPath
        stringByAppendingPathComponent:@"OpenJDKRuntime.framework/OpenJDKRuntime"];
}

static NSString *ensureDir(NSString *path) {
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

static NSString *appSupportDir(void) {
    return ensureDir(NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject);
}

/// Describes and clears a pending Java exception; nil if there was none.
static NSString *takeException(JNIEnv *env) {
    if (!env->ExceptionCheck()) return nil;
    jthrowable t = env->ExceptionOccurred();
    env->ExceptionDescribe(); // full Java stack trace to stderr
    env->ExceptionClear();
    NSString *text = @"Java exception";
    jclass objClass = env->FindClass("java/lang/Object");
    jmethodID toString = env->GetMethodID(objClass, "toString", "()Ljava/lang/String;");
    jstring s = (jstring)env->CallObjectMethod(t, toString);
    if (s && !env->ExceptionCheck()) {
        const char *c = env->GetStringUTFChars(s, nullptr);
        text = [NSString stringWithUTF8String:c];
        env->ReleaseStringUTFChars(s, c);
    }
    env->ExceptionClear();
    return text;
}

// MARK: - A6 completions (JNI → Swift)
//
// YomiHost runs each request on a Java worker thread and answers through YomiNative.complete / completeImage, bound
// below with RegisterNatives. Tickets map to the waiting completion block. The callbacks run on JVM-attached Java
// threads: copy the result out, then hand it to a dispatch queue so Java isn't held while Swift resumes.

typedef void (^CallCompletion)(NSInteger, NSData *, NSString *);
typedef void (^ImageCompletion)(NSInteger, NSString *, NSData *);

static os_unfair_lock pendingLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSNumber *, id> *pendingBlocks(void) {
    static NSMutableDictionary *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary new]; });
    return d;
}
static std::atomic<int64_t> nextTicket{1};

static int64_t addPending(id block) {
    int64_t ticket = nextTicket.fetch_add(1);
    os_unfair_lock_lock(&pendingLock);
    pendingBlocks()[@(ticket)] = [block copy];
    os_unfair_lock_unlock(&pendingLock);
    return ticket;
}

static id takePending(int64_t ticket) {
    os_unfair_lock_lock(&pendingLock);
    id block = pendingBlocks()[@(ticket)];
    [pendingBlocks() removeObjectForKey:@(ticket)];
    os_unfair_lock_unlock(&pendingLock);
    return block;
}

static NSData *copyBytes(JNIEnv *env, jbyteArray array) {
    if (!array) return nil;
    jsize n = env->GetArrayLength(array);
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)n];
    if (n > 0) env->GetByteArrayRegion(array, 0, n, (jbyte *)data.mutableBytes);
    return data;
}

static NSString *copyString(JNIEnv *env, jstring s) {
    if (!s) return nil;
    const char *c = env->GetStringUTFChars(s, nullptr);
    NSString *out = c ? [NSString stringWithUTF8String:c] : nil;
    if (c) env->ReleaseStringUTFChars(s, c);
    return out;
}

static dispatch_queue_t completionQueue(void) { return dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0); }

static void JNICALL nativeComplete(JNIEnv *env, jclass, jlong ticket, jint status, jbyteArray body, jstring extId) {
    CallCompletion done = takePending(ticket);
    if (!done) return;
    NSData *data = copyBytes(env, body) ?: [NSData data];
    NSString *handle = copyString(env, extId);
    dispatch_async(completionQueue(), ^{ done(status, data, handle); });
}

static void JNICALL nativeCompleteImage(JNIEnv *env, jclass, jlong ticket, jint status, jstring type, jbyteArray bytes) {
    ImageCompletion done = takePending(ticket);
    if (!done) return;
    NSString *contentType = copyString(env, type);
    NSData *data = copyBytes(env, bytes);
    dispatch_async(completionQueue(), ^{ done(status, contentType, data); });
}

static NSData *errorBody(NSString *message) {
    return [NSJSONSerialization dataWithJSONObject:@{@"error": message ?: @"Keiyoushi failed", @"code": @500}
                                           options:0 error:nil] ?: [NSData data];
}

@implementation KeiyoushiJVMHost {
    NSThread *_thread;
    NSCondition *_cond;
    NSMutableArray<void (^)(JNIEnv *)> *_work;
    JavaVM *_vm;
    NSString *_createError;
    BOOL _engineReady;       // YomiHost.start succeeded and the natives are bound (JVM thread only)
    jclass _yomiHost;        // global ref, JVM thread only
    jmethodID _callMethod;
    jmethodID _imageMethod;
}

+ (KeiyoushiJVMHost *)shared {
    static KeiyoushiJVMHost *host;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ host = [KeiyoushiJVMHost new]; });
    return host;
}

+ (BOOL)isAvailable {
    return [[NSFileManager defaultManager] fileExistsAtPath:runtimeBinaryPath()];
}

- (instancetype)init {
    if ((self = [super init])) {
        _cond = [NSCondition new];
        _work = [NSMutableArray new];
    }
    return self;
}

- (void)enqueue:(void (^)(JNIEnv *))block {
    [_cond lock];
    if (!_thread) {
        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(jvmThreadMain) object:nil];
        _thread.name = @"YomiJVM";
        _thread.stackSize = kJVMThreadStack;
        _thread.qualityOfService = NSQualityOfServiceUserInitiated;
        [_thread start];
    }
    [_work addObject:block];
    [_cond signal];
    [_cond unlock];
}

- (void)jvmThreadMain {
    JNIEnv *env = [self createVM];
    for (;;) {
        [_cond lock];
        while (_work.count == 0) [_cond wait];
        void (^block)(JNIEnv *) = _work.firstObject;
        [_work removeObjectAtIndex:0];
        [_cond unlock];
        block(env);
    }
}

- (JNIEnv *)createVM {
    void *lib = dlopen(runtimeBinaryPath().UTF8String, RTLD_NOW | RTLD_GLOBAL);
    CreateJavaVMFn create = lib ? (CreateJavaVMFn)dlsym(lib, "JNI_CreateJavaVM") : nullptr;
    if (!create) {
        _createError = [NSString stringWithFormat:@"Keiyoushi runtime not loadable: %s", dlerror() ?: "missing"];
        return nullptr;
    }
    // On iOS, HotSpot ignores -Djava.home and uses "<directory of the JVM binary>/lib" — the framework ships its
    // Java home there (scripts/keiyoushi-poc/build-runtime-framework.sh).
    NSString *javaHome = [[NSBundle mainBundle].privateFrameworksPath
        stringByAppendingPathComponent:@"OpenJDKRuntime.framework/lib"];
    NSString *payload = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Keiyoushi"];
    NSString *tmp = ensureDir([NSTemporaryDirectory() stringByAppendingPathComponent:@"MihonExtensions"]);

    std::vector<std::string> opts = {
        std::string("-Djava.class.path=") + [payload stringByAppendingPathComponent:@"MExtensionServer.jar"].UTF8String,
        std::string("-Xbootclasspath/a:") + [payload stringByAppendingPathComponent:@"java-logging-shim.jar"].UTF8String,
        std::string("-Djava.io.tmpdir=") + tmp.UTF8String,
        std::string("-Duser.home=") + appSupportDir().UTF8String,
        std::string("-Djavax.net.ssl.trustStore=") + [javaHome stringByAppendingPathComponent:@"lib/security/cacerts"].UTF8String,
        "-Djava.awt.headless=true",
        "-Dfile.encoding=UTF-8",
        "-Djava.net.preferIPv4Stack=true",
        "-Dorg.slf4j.simpleLogger.defaultLogLevel=warn",
        "-XX:+UseSerialGC",
        "-Xms128m",
        "-Xmx512m",
        "-Xss8m",
    };
#if DEBUG
    // S159: launch with -keiyoushiWireStats to print a "YOMI-WIRE ..." line per request to the console
    // (WireStatsInterceptor, server patch) — the first request on a connection carries the TLS handshake.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"-keiyoushiWireStats"]) {
        opts.push_back("-Dyomi.wireStats=true");
    }
#endif
    std::vector<JavaVMOption> jopts(opts.size());
    for (size_t i = 0; i < opts.size(); i++) {
        jopts[i].optionString = const_cast<char *>(opts[i].c_str());
        jopts[i].extraInfo = nullptr;
    }
    JavaVMInitArgs args = {};
    args.version = JNI_VERSION_21;
    args.nOptions = (jint)jopts.size();
    args.options = jopts.data();
    args.ignoreUnrecognized = JNI_FALSE;

    JNIEnv *env = nullptr;
    NSTimeInterval t0 = [NSProcessInfo processInfo].systemUptime;
    jint rc = create(&_vm, (void **)&env, &args);
    NSLog(@"[Keiyoushi] JNI_CreateJavaVM rc=%d in %.0f ms", rc, ([NSProcessInfo processInfo].systemUptime - t0) * 1000);
    if (rc != JNI_OK) {
        _createError = [NSString stringWithFormat:@"JNI_CreateJavaVM failed: %d", rc];
        return nullptr;
    }
    return env;
}

- (void)startWithToken:(NSString *)token completion:(void (^)(NSInteger, NSString *))completion {
    NSString *tokenCopy = [token copy];
    [self enqueue:^(JNIEnv *env) {
        NSInteger port = 0;
        NSString *error = self->_createError;
        if (env) {
            jclass cls = env->FindClass("mextensionserver/EmbeddedBridge");
            // start(port, appDir, token) — our server patch (S191). Never fall back to the unlocked 2-argument start.
            jmethodID start = cls ? env->GetStaticMethodID(cls, "start", "(ILjava/lang/String;Ljava/lang/String;)I")
                                  : nullptr;
            if ((error = takeException(env)) == nil && !start) {
                error = @"The Keiyoushi runtime is out of date (no locked start).";
            }
            if (error == nil && start) {
                NSString *dir = ensureDir([appSupportDir() stringByAppendingPathComponent:@"Keiyoushi/bridge"]);
                jstring jdir = env->NewStringUTF(dir.UTF8String);
                jstring jtoken = env->NewStringUTF(tokenCopy.UTF8String);
                NSTimeInterval t0 = [NSProcessInfo processInfo].systemUptime;
                port = env->CallStaticIntMethod(cls, start, 0, jdir, jtoken);
                env->DeleteLocalRef(jtoken);
                env->DeleteLocalRef(jdir);
                if ((error = takeException(env))) port = 0;
                NSLog(@"[Keiyoushi] EmbeddedBridge.start -> port %ld in %.0f ms", (long)port,
                      ([NSProcessInfo processInfo].systemUptime - t0) * 1000);
            }
            if (cls) env->DeleteLocalRef(cls);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(port, error); });
    }];
}

- (void)pauseBridge {
    if (!_thread) return; // never started — nothing to pause
    [self enqueue:^(JNIEnv *env) {
        if (!env) return;
        jclass cls = env->FindClass("mextensionserver/EmbeddedBridge");
        jmethodID pause = cls ? env->GetStaticMethodID(cls, "pause", "()V") : nullptr;
        if (pause) env->CallStaticVoidMethod(cls, pause);
        takeException(env);
        if (cls) env->DeleteLocalRef(cls);
    }];
}

// MARK: - A6: direct JNI transport

/// JVM thread only. Binds the natives, starts YomiHost, caches its methods. nil on success.
- (NSString *)prepareEngine:(JNIEnv *)env apkDirectory:(NSString *)apkDirectory {
    if (!env) return _createError ?: @"The extension runtime didn't start.";
    jclass native = env->FindClass("mextensionserver/YomiNative");
    jclass host = native ? env->FindClass("mextensionserver/YomiHost") : nullptr;
    NSString *error = takeException(env);
    if (!error && (!native || !host)) error = @"The Keiyoushi runtime is out of date (no direct transport).";
    if (!error && !_engineReady) {
        JNINativeMethod methods[] = {
            {(char *)"complete", (char *)"(JI[BLjava/lang/String;)V", (void *)nativeComplete},
            {(char *)"completeImage", (char *)"(JILjava/lang/String;[B)V", (void *)nativeCompleteImage},
        };
        if (env->RegisterNatives(native, methods, 2) != JNI_OK) error = takeException(env) ?: @"RegisterNatives failed";
    }
    jmethodID start = nullptr;
    if (!error) {
        start = env->GetStaticMethodID(host, "start", "(Ljava/lang/String;Ljava/lang/String;)V");
        _callMethod = env->GetStaticMethodID(host, "call", "([BLjava/lang/String;Ljava/lang/String;J)V");
        _imageMethod = env->GetStaticMethodID(host, "image", "(Ljava/lang/String;J)V");
        error = takeException(env);
        if (!error && (!start || !_callMethod || !_imageMethod)) error = @"The Keiyoushi runtime is out of date.";
    }
    if (!error) {
        NSString *dir = ensureDir([appSupportDir() stringByAppendingPathComponent:@"Keiyoushi/bridge"]);
        jstring jdir = env->NewStringUTF(dir.UTF8String);
        jstring japks = env->NewStringUTF(apkDirectory.UTF8String);
        NSTimeInterval t0 = [NSProcessInfo processInfo].systemUptime;
        env->CallStaticVoidMethod(host, start, jdir, japks);
        env->DeleteLocalRef(japks);
        env->DeleteLocalRef(jdir);
        error = takeException(env);
        if (!_engineReady) {
            NSLog(@"[Keiyoushi] YomiHost.start in %.0f ms%@", ([NSProcessInfo processInfo].systemUptime - t0) * 1000,
                  error ? [@" FAILED: " stringByAppendingString:error] : @"");
        }
    }
    if (!error && !_yomiHost) _yomiHost = (jclass)env->NewGlobalRef(host);
    if (host) env->DeleteLocalRef(host);
    if (native) env->DeleteLocalRef(native);
    if (!error) _engineReady = YES;
    return error;
}

- (void)startEngineWithAPKDirectory:(NSString *)apkDirectory completion:(void (^)(NSString *))completion {
    NSString *dir = [apkDirectory copy];
    [self enqueue:^(JNIEnv *env) {
        NSString *error = [self prepareEngine:env apkDirectory:dir];
        dispatch_async(completionQueue(), ^{ completion(error); });
    }];
}

- (void)callWithRequest:(NSData *)json
              userAgent:(NSString *)userAgent
                cookies:(NSString *)cookies
             completion:(void (^)(NSInteger, NSData *, NSString *))completion {
    NSData *body = [json copy];
    NSString *ua = [userAgent copy], *cookie = [cookies copy];
    int64_t ticket = addPending(completion);
    [self enqueue:^(JNIEnv *env) {
        NSString *error = nil;
        if (!env || !self->_engineReady) {
            error = self->_createError ?: @"The extension runtime isn't started.";
        } else {
            jbyteArray jbody = env->NewByteArray((jsize)body.length);
            if (jbody) env->SetByteArrayRegion(jbody, 0, (jsize)body.length, (const jbyte *)body.bytes);
            jstring jua = env->NewStringUTF(ua.UTF8String);
            jstring jcookie = cookie.length ? env->NewStringUTF(cookie.UTF8String) : nullptr;
            if ((error = takeException(env)) == nil) {
                env->CallStaticVoidMethod(self->_yomiHost, self->_callMethod, jbody, jua, jcookie, (jlong)ticket);
                error = takeException(env);
            }
            if (jcookie) env->DeleteLocalRef(jcookie);
            if (jua) env->DeleteLocalRef(jua);
            if (jbody) env->DeleteLocalRef(jbody);
        }
        if (error) {
            CallCompletion done = takePending(ticket);
            if (done) dispatch_async(completionQueue(), ^{ done(500, errorBody(error), nil); });
        }
    }];
}

- (void)imageWithId:(NSString *)imageId completion:(void (^)(NSInteger, NSString *, NSData *))completion {
    NSString *imageKey = [imageId copy];
    int64_t ticket = addPending(completion);
    [self enqueue:^(JNIEnv *env) {
        NSString *error = nil;
        if (!env || !self->_engineReady) {
            error = @"not started";
        } else {
            jstring jid = env->NewStringUTF(imageKey.UTF8String);
            if ((error = takeException(env)) == nil) {
                env->CallStaticVoidMethod(self->_yomiHost, self->_imageMethod, jid, (jlong)ticket);
                error = takeException(env);
            }
            if (jid) env->DeleteLocalRef(jid);
        }
        if (error) {
            ImageCompletion done = takePending(ticket);
            if (done) dispatch_async(completionQueue(), ^{ done(503, nil, nil); });
        }
    }];
}

@end
