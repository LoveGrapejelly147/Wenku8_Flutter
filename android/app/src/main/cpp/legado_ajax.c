#include <jni.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef jint (*GetCreatedVMs)(JavaVM **, jsize, jsize *);

static JavaVM *legado_vm(void) {
    void *art = dlopen("libart.so", RTLD_NOW);
    if (!art) return NULL;
    GetCreatedVMs get = (GetCreatedVMs)dlsym(art, "JNI_GetCreatedJavaVMs");
    if (!get) return NULL;
    JavaVM *vm = NULL;
    jsize count = 0;
    if (get(&vm, 1, &count) != JNI_OK || count < 1) return NULL;
    return vm;
}

static jstring legado_jstring(JNIEnv *env, const char *text) {
    return (*env)->NewStringUTF(env, text == NULL ? "" : text);
}

char *legado_ajax(const char *url, const char *method, const char *body, const char *cookie) {
    JavaVM *java = legado_vm();
    if (!java) return strdup("\x1e" "ERR" "\x1e" "无法连接 Android 网络");
    JNIEnv *env = NULL;
    int detach = 0;
    if ((*java)->GetEnv(java, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
        if ((*java)->AttachCurrentThread(java, &env, NULL) != JNI_OK) {
            return strdup("\x1e" "ERR" "\x1e" "无法连接 Android 网络");
        }
        detach = 1;
    }
    jclass urlClass = (*env)->FindClass(env, "java/net/URL");
    jmethodID urlInit = (*env)->GetMethodID(env, urlClass, "<init>", "(Ljava/lang/String;)V");
    jstring jUrl = legado_jstring(env, url);
    jobject urlObject = (*env)->NewObject(env, urlClass, urlInit, jUrl);
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionClear(env);
        if (detach) (*java)->DetachCurrentThread(java);
        return strdup("\x1e" "ERR" "\x1e" "java.ajax 地址无效");
    }
    jmethodID open = (*env)->GetMethodID(env, urlClass, "openConnection", "()Ljava/net/URLConnection;");
    jobject connection = (*env)->CallObjectMethod(env, urlObject, open);
    jclass http = (*env)->FindClass(env, "java/net/HttpURLConnection");
    jmethodID setMethod = (*env)->GetMethodID(env, http, "setRequestMethod", "(Ljava/lang/String;)V");
    jmethodID setConnect = (*env)->GetMethodID(env, http, "setConnectTimeout", "(I)V");
    jmethodID setRead = (*env)->GetMethodID(env, http, "setReadTimeout", "(I)V");
    jmethodID setProperty = (*env)->GetMethodID(env, http, "setRequestProperty", "(Ljava/lang/String;Ljava/lang/String;)V");
    jmethodID setDoOutput = (*env)->GetMethodID(env, http, "setDoOutput", "(Z)V");
    const char *verb = method == NULL || method[0] == '\0' ? "GET" : method;
    (*env)->CallVoidMethod(env, connection, setMethod, legado_jstring(env, verb));
    (*env)->CallVoidMethod(env, connection, setConnect, 8000);
    (*env)->CallVoidMethod(env, connection, setRead, 8000);
    (*env)->CallVoidMethod(env, connection, setProperty, legado_jstring(env, "User-Agent"),
                           legado_jstring(env, "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36"));
    if (cookie != NULL && cookie[0] != '\0') {
        (*env)->CallVoidMethod(env, connection, setProperty, legado_jstring(env, "Cookie"), legado_jstring(env, cookie));
    }
    if (body != NULL && body[0] != '\0' && strcmp(verb, "GET") != 0 && strcmp(verb, "HEAD") != 0) {
        (*env)->CallVoidMethod(env, connection, setDoOutput, JNI_TRUE);
        jmethodID getOutput = (*env)->GetMethodID(env, http, "getOutputStream", "()Ljava/io/OutputStream;");
        jobject output = (*env)->CallObjectMethod(env, connection, getOutput);
        jclass stream = (*env)->FindClass(env, "java/io/OutputStream");
        jmethodID write = (*env)->GetMethodID(env, stream, "write", "([B)V");
        jsize size = (jsize)strlen(body);
        jbyteArray bytes = (*env)->NewByteArray(env, size);
        (*env)->SetByteArrayRegion(env, bytes, 0, size, (const jbyte *)body);
        (*env)->CallVoidMethod(env, output, write, bytes);
    }
    jmethodID getCode = (*env)->GetMethodID(env, http, "getResponseCode", "()I");
    jint code = (*env)->CallIntMethod(env, connection, getCode);
    jmethodID getStream = (*env)->GetMethodID(env, http, code >= 400 ? "getErrorStream" : "getInputStream", "()Ljava/io/InputStream;");
    jobject input = (*env)->CallObjectMethod(env, connection, getStream);
    if ((*env)->ExceptionCheck(env) || input == NULL) {
        (*env)->ExceptionClear(env);
        if (detach) (*java)->DetachCurrentThread(java);
        char *message = (char *)malloc(32);
        if (!message) return NULL;
        snprintf(message, 32, "\x1e%d\x1e", code);
        return message;
    }
    jclass readerClass = (*env)->FindClass(env, "java/io/InputStreamReader");
    jmethodID readerInit = (*env)->GetMethodID(env, readerClass, "<init>", "(Ljava/io/InputStream;Ljava/lang/String;)V");
    jobject reader = (*env)->NewObject(env, readerClass, readerInit, input, legado_jstring(env, "UTF-8"));
    jclass buffered = (*env)->FindClass(env, "java/io/BufferedReader");
    jmethodID bufferedInit = (*env)->GetMethodID(env, buffered, "<init>", "(Ljava/io/Reader;)V");
    jobject bufferedReader = (*env)->NewObject(env, buffered, bufferedInit, reader);
    jmethodID readLine = (*env)->GetMethodID(env, buffered, "readLine", "()Ljava/lang/String;");
    jclass builderClass = (*env)->FindClass(env, "java/lang/StringBuilder");
    jobject builder = (*env)->NewObject(env, builderClass, (*env)->GetMethodID(env, builderClass, "<init>", "()V"));
    jmethodID append = (*env)->GetMethodID(env, builderClass, "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;");
    int lines = 0;
    while (lines < 20000) {
        jstring line = (*env)->CallObjectMethod(env, bufferedReader, readLine);
        if ((*env)->ExceptionCheck(env) || line == NULL) {
            (*env)->ExceptionClear(env);
            break;
        }
        if (lines > 0) (*env)->CallObjectMethod(env, builder, append, legado_jstring(env, "\n"));
        (*env)->CallObjectMethod(env, builder, append, line);
        lines++;
    }
    jmethodID toString = (*env)->GetMethodID(env, builderClass, "toString", "()Ljava/lang/String;");
    jstring text = (*env)->CallObjectMethod(env, builder, toString);
    const char *utf = (*env)->GetStringUTFChars(env, text, NULL);
    const char *payload = utf == NULL ? "" : utf;
    const size_t bytes = strlen(payload) + 32;
    char *owned = (char *)malloc(bytes);
    if (owned) snprintf(owned, bytes, "\x1e%d\x1e%s", code, payload);
    if (utf) (*env)->ReleaseStringUTFChars(env, text, utf);
    if (detach) (*java)->DetachCurrentThread(java);
    return owned;
}

void legado_free(char *text) { free(text); }
