#ifndef ZENOH_DART_H
#define ZENOH_DART_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
// #include <zenoh.h>

#if __has_include(<zenoh.h>)
    #include <zenoh.h>
#elif __has_include("zenoh.h")
    #include "zenoh.h"
#else
    #error "zenoh.h not found!"
#endif

#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

// Define proper export macros for Android
#if defined(_WIN32)
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#elif defined(__GNUC__) && __GNUC__ >= 4
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FFI_PLUGIN_EXPORT
#endif

// LOG MACRO for debugging
//#define LOG_DEBUG(fmt, ...) printf("ZENOH_DART DEBUG: " fmt "\n", ##__VA_ARGS__)
//#else
//#define LOG_DEBUG(fmt, ...) do {} while (0)
//#endif


// Callback function pointer type for Flutter
typedef void (*SubscriberCallback)(const char* key, const char* value, const char* kind, const char* attachment, int subscriber_id);

// TODO: unidentified issue with multiple subscribers, need to investigate
// Define maximum number of subscribers
// Maximum dictionary of concurrent subscribers
#define MAX_SUBSCRIBERS 255


// Subscriber structure
typedef struct {
    z_owned_subscriber_t subscriber;
    SubscriberCallback callback;
    bool active;
    int id;
    char key_expr[256];
} subscriber_t;

// Global zenoh session variable
static z_owned_session_t session;
static bool session_opened = false;

// Global variables for zenoh_get reply handling
static bool reply_received = false;
static char *last_received_value = NULL;

// Global variables for zenoh_put publisher handling
static z_owned_publisher_t global_publisher;
static bool publisher_declared = false;
static char current_publisher_key[256] = "";

// Multiple subscribers support
static subscriber_t g_subscribers[MAX_SUBSCRIBERS];
static int g_next_subscriber_id = 0;

// Function declarations
FFI_PLUGIN_EXPORT int zenoh_init(void);
FFI_PLUGIN_EXPORT void zenoh_cleanup(void);
FFI_PLUGIN_EXPORT int zenoh_open_session(const char* mode, const char* endpoint);
FFI_PLUGIN_EXPORT void zenoh_close_session(void);
FFI_PLUGIN_EXPORT int zenoh_put(const char* key, const char* value);
FFI_PLUGIN_EXPORT int zenoh_publish(const char* key, const char* value);
FFI_PLUGIN_EXPORT char* zenoh_get(const char* key);
FFI_PLUGIN_EXPORT char* zenoh_get_with_handler(const char* key);
FFI_PLUGIN_EXPORT void zenoh_free_string(char* str);
FFI_PLUGIN_EXPORT int zenoh_subscribe(const char* key_expr, SubscriberCallback callback);
FFI_PLUGIN_EXPORT void zenoh_unsubscribe(int subscriber_id);
FFI_PLUGIN_EXPORT void zenoh_unsubscribe_all(void);

#endif // ZENOH_DART_H