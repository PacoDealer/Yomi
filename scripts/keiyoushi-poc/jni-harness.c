// A6 Mac check: same JNI calls as KeiyoushiJVMHost.mm (RegisterNatives, YomiHost.start/call/image, callbacks).
#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER; static pthread_cond_t c = PTHREAD_COND_INITIALIZER;
static int done = 0, lastStatus = 0; static char *lastBody = NULL, *lastExt = NULL; static long imgBytes = -1;
static void JNICALL complete(JNIEnv *e, jclass k, jlong t, jint st, jbyteArray b, jstring ext) {
  jsize n = (*e)->GetArrayLength(e, b); char *buf = malloc(n + 1); (*e)->GetByteArrayRegion(e, b, 0, n, (jbyte*)buf); buf[n] = 0;
  pthread_mutex_lock(&m); lastStatus = st; free(lastBody); lastBody = buf; free(lastExt); lastExt = NULL;
  if (ext) { const char *s = (*e)->GetStringUTFChars(e, ext, 0); lastExt = strdup(s); (*e)->ReleaseStringUTFChars(e, ext, s); }
  done = 1; pthread_cond_signal(&c); pthread_mutex_unlock(&m);
}
static void JNICALL completeImage(JNIEnv *e, jclass k, jlong t, jint st, jstring ty, jbyteArray b) {
  pthread_mutex_lock(&m); lastStatus = st; imgBytes = b ? (*e)->GetArrayLength(e, b) : -1; done = 1; pthread_cond_signal(&c); pthread_mutex_unlock(&m);
}
static JNIEnv *env; static jclass host; static jmethodID mcall;
static void waitDone(void) { pthread_mutex_lock(&m); while (!done) pthread_cond_wait(&c, &m); done = 0; pthread_mutex_unlock(&m); }
static void call(const char *json, long ticket) {
  jbyteArray b = (*env)->NewByteArray(env, strlen(json)); (*env)->SetByteArrayRegion(env, b, 0, strlen(json), (const jbyte*)json);
  (*env)->CallStaticVoidMethod(env, host, mcall, b, (*env)->NewStringUTF(env, "Yomi-Harness"), NULL, (jlong)ticket);
  if ((*env)->ExceptionCheck(env)) { (*env)->ExceptionDescribe(env); exit(2); }
  waitDone();
}
int main(int argc, char **argv) {
  const char *jar = argv[1], *shim = argv[2], *apkdir = argv[3], *apk = argv[4], *app = argv[5];
  char o1[2048], o2[2048]; snprintf(o1, sizeof o1, "-Djava.class.path=%s", jar); snprintf(o2, sizeof o2, "-Xbootclasspath/a:%s", shim);
  JavaVMOption opts[] = {{o1}, {o2}, {"-Xint"}, {"-Xss8m"}, {"-XX:+UseSerialGC"}, {"-Djava.awt.headless=true"}, {"-Dorg.slf4j.simpleLogger.defaultLogLevel=warn"}};
  JavaVMInitArgs a = {JNI_VERSION_21, 7, opts, JNI_FALSE}; JavaVM *vm;
  if (JNI_CreateJavaVM(&vm, (void**)&env, &a) != JNI_OK) { puts("create failed"); return 1; }
  jclass nat = (*env)->FindClass(env, "mextensionserver/YomiNative");
  host = (*env)->FindClass(env, "mextensionserver/YomiHost");
  JNINativeMethod ms[] = {{"complete", "(JI[BLjava/lang/String;)V", complete}, {"completeImage", "(JILjava/lang/String;[B)V", completeImage}};
  if (!nat || !host || (*env)->RegisterNatives(env, nat, ms, 2) != 0) { (*env)->ExceptionDescribe(env); return 1; }
  jmethodID start = (*env)->GetStaticMethodID(env, host, "start", "(Ljava/lang/String;Ljava/lang/String;)V");
  mcall = (*env)->GetStaticMethodID(env, host, "call", "([BLjava/lang/String;Ljava/lang/String;J)V");
  jmethodID mimg = (*env)->GetStaticMethodID(env, host, "image", "(Ljava/lang/String;J)V");
  (*env)->CallStaticVoidMethod(env, host, start, (*env)->NewStringUTF(env, app), (*env)->NewStringUTF(env, apkdir));
  if ((*env)->ExceptionCheck(env)) { (*env)->ExceptionDescribe(env); return 1; }
  char json[4096];
  snprintf(json, sizeof json, "{\"method\":\"getPopularManga\",\"apkPath\":\"%s\",\"page\":1}", apk); call(json, 1);
  printf("popular: %d ext=%s %.150s\n", lastStatus, lastExt ? lastExt : "-", lastBody);
  char *ext = lastExt ? strdup(lastExt) : NULL;
  snprintf(json, sizeof json, "{\"method\":\"getPopularManga\",\"extensionId\":\"%s\",\"page\":2}", ext ? ext : "x"); call(json, 2);
  printf("popular p2 by handle: %d %.80s\n", lastStatus, lastBody);
  call("{\"method\":\"getPopularManga\",\"apkPath\":\"/etc/passwd\",\"page\":1}", 3);
  printf("outside apk dir: %d %.120s\n", lastStatus, lastBody);
  (*env)->CallStaticVoidMethod(env, host, mimg, (*env)->NewStringUTF(env, "nope"), (jlong)4); waitDone();
  printf("unknown image: %d bytes=%ld\n", lastStatus, imgBytes);
  return 0;
}
