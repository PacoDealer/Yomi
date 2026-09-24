#import "KeiyoushiJVMHost.h"
#include "JNI/jni.h"
#include <dlfcn.h>
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

@implementation KeiyoushiJVMHost {
    NSThread *_thread;
    NSCondition *_cond;
    NSMutableArray<void (^)(JNIEnv *)> *_work;
    JavaVM *_vm;
    NSString *_createError;
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

- (void)startWithCompletion:(void (^)(NSInteger, NSString *))completion {
    [self enqueue:^(JNIEnv *env) {
        NSInteger port = 0;
        NSString *error = self->_createError;
        if (env) {
            jclass cls = env->FindClass("mextensionserver/EmbeddedBridge");
            jmethodID start = cls ? env->GetStaticMethodID(cls, "start", "(ILjava/lang/String;)I") : nullptr;
            if ((error = takeException(env)) == nil && start) {
                NSString *dir = ensureDir([appSupportDir() stringByAppendingPathComponent:@"Keiyoushi/bridge"]);
                jstring jdir = env->NewStringUTF(dir.UTF8String);
                NSTimeInterval t0 = [NSProcessInfo processInfo].systemUptime;
                port = env->CallStaticIntMethod(cls, start, 0, jdir);
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

@end
