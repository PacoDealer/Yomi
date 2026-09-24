#import "JVMHost.h"
#include <jni.h>
#include <string>
#include <vector>

static const NSUInteger kJVMThreadStack = 16 * 1024 * 1024;

@implementation JVMHost {
    NSThread *_thread;
    NSCondition *_cond;
    NSMutableArray<void (^)(JNIEnv *)> *_work;
    JavaVM *_vm;
    double _createMs;
    NSString *_createError;
}

+ (JVMHost *)shared {
    static JVMHost *host;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ host = [JVMHost new]; });
    return host;
}

- (instancetype)init {
    if ((self = [super init])) {
        _cond = [NSCondition new];
        _work = [NSMutableArray new];
    }
    return self;
}

static double nowMs(void) { return [NSProcessInfo processInfo].systemUptime * 1000.0; }

static NSString *ensureDir(NSString *path) {
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

/// Describes and clears a pending Java exception; nil if there was none.
static NSString *takeException(JNIEnv *env) {
    if (!env->ExceptionCheck()) return nil;
    jthrowable t = env->ExceptionOccurred();
    env->ExceptionDescribe(); // full stack trace to stderr (devicectl --console shows it)
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
    // Fixed by HotSpot on iOS: "<directory of the JVM binary>/lib" (-Djava.home is ignored), see build-runtime-framework.sh.
    NSString *javaHome = [[NSBundle mainBundle].privateFrameworksPath
        stringByAppendingPathComponent:@"OpenJDKRuntime.framework/lib"];
    NSString *res = [NSBundle mainBundle].resourcePath;
    NSString *appSupport = ensureDir(NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject);
    NSString *tmp = ensureDir([NSTemporaryDirectory() stringByAppendingPathComponent:@"MihonExtensions"]);

    std::vector<std::string> opts = {
        std::string("-Djava.class.path=") + [res stringByAppendingPathComponent:@"BridgeFiles/MExtensionServer.jar"].UTF8String,
        std::string("-Xbootclasspath/a:") + [res stringByAppendingPathComponent:@"BridgeFiles/java-logging-shim.jar"].UTF8String,
        std::string("-Djava.io.tmpdir=") + tmp.UTF8String,
        std::string("-Duser.home=") + appSupport.UTF8String,
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
        fprintf(stderr, "[JVMHost] option %s\n", opts[i].c_str());
    }
    JavaVMInitArgs args = {};
    args.version = JNI_VERSION_21;
    args.nOptions = (jint)jopts.size();
    args.options = jopts.data();
    args.ignoreUnrecognized = JNI_FALSE;

    JNIEnv *env = nullptr;
    double t0 = nowMs();
    jint rc = JNI_CreateJavaVM(&_vm, (void **)&env, &args);
    _createMs = nowMs() - t0;
    if (rc != JNI_OK) {
        _createError = [NSString stringWithFormat:@"JNI_CreateJavaVM failed: %d", rc];
        env = nullptr;
    }
    fprintf(stderr, "[JVMHost] JNI_CreateJavaVM rc=%d in %.0f ms\n", rc, _createMs);
    return env;
}

- (void)startWithCompletion:(void (^)(NSInteger, double, double, NSString *))completion {
    [self enqueue:^(JNIEnv *env) {
        NSInteger port = 0;
        double bridgeMs = 0;
        NSString *error = self->_createError;
        double createMs = self->_createMs;
        self->_createMs = 0; // report VM creation only once
        if (env) {
            jclass cls = env->FindClass("mextensionserver/EmbeddedBridge");
            jmethodID start = cls ? env->GetStaticMethodID(cls, "start", "(ILjava/lang/String;)I") : nullptr;
            if ((error = takeException(env)) == nil && start) {
                NSString *dir = ensureDir([NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                    stringByAppendingPathComponent:@"MExtension"]);
                jstring jdir = env->NewStringUTF(dir.UTF8String);
                double t0 = nowMs();
                port = env->CallStaticIntMethod(cls, start, 0, jdir);
                bridgeMs = nowMs() - t0;
                env->DeleteLocalRef(jdir);
                if ((error = takeException(env))) port = 0;
            }
            if (cls) env->DeleteLocalRef(cls);
            fprintf(stderr, "[JVMHost] EmbeddedBridge.start -> port %ld in %.0f ms %s\n",
                    (long)port, bridgeMs, error.UTF8String ?: "");
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(port, createMs, bridgeMs, error); });
    }];
}

- (void)pauseBridge {
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
