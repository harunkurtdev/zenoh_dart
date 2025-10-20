// zenoh_dart.h - Header file
#ifndef ZENOH_DART_H
#define ZENOH_DART_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <zenoh.h>

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

// Callback function pointer type for Flutter
typedef void (*SubscriberCallback)(const char* key, const char* value, const char* kind, const char* attachment, int subscriber_id);

// Subscriber structure
typedef struct subscriber_node {
    z_owned_subscriber_t subscriber;
    SubscriberCallback callback;
    bool active;
    int id;
    char key_expr[256];
    struct subscriber_node* next;
} subscriber_node_t;

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

// Linked list for subscribers
static subscriber_node_t* g_subscribers_head = NULL;
static int g_next_subscriber_id = 0;
static pthread_mutex_t g_subscribers_mutex = PTHREAD_MUTEX_INITIALIZER;

// Function declarations
FFI_PLUGIN_EXPORT int zenoh_init();
FFI_PLUGIN_EXPORT void zenoh_cleanup();
FFI_PLUGIN_EXPORT int zenoh_open_session();
FFI_PLUGIN_EXPORT void zenoh_close_session();
FFI_PLUGIN_EXPORT int zenoh_put(const char* key, const char* value);
FFI_PLUGIN_EXPORT int zenoh_publish(const char* key, const char* value);
FFI_PLUGIN_EXPORT char* zenoh_get(const char* key);
FFI_PLUGIN_EXPORT char* zenoh_get_with_handler(const char* key);
FFI_PLUGIN_EXPORT void zenoh_free_string(char* str);
FFI_PLUGIN_EXPORT int zenoh_subscribe(const char* key_expr, SubscriberCallback callback);
FFI_PLUGIN_EXPORT void zenoh_unsubscribe(int subscriber_id);
FFI_PLUGIN_EXPORT void zenoh_unsubscribe_all();
FFI_PLUGIN_EXPORT int zenoh_get_subscriber_count();

#endif // ZENOH_DART_H