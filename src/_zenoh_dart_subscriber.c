#include "zenoh_dart.h"

// Find free subscriber slot
static int find_free_subscriber_slot()
{
    for (int i = 0; i < MAX_SUBSCRIBERS; i++)
    {
        if (!g_subscribers[i].active)
        {
            return i;
        }
    }
    return -1;
}

// Find subscriber by ID
static subscriber_t *find_subscriber_by_id(int subscriber_id)
{
    for (int i = 0; i < MAX_SUBSCRIBERS; i++)
    {
        if (g_subscribers[i].active && g_subscribers[i].id == subscriber_id)
        {
            return &g_subscribers[i];
        }
    }
    return NULL;
}

// Data handler for subscriber - called when data is received
void data_handler(const z_loaned_sample_t *sample, void *arg)
{
    int subscriber_id = *(int *)arg;
    subscriber_t *sub = find_subscriber_by_id(subscriber_id);

    if (sub == NULL || sub->callback == NULL)
    {
        printf("Subscriber not found or no callback: %d\n", subscriber_id);
        return;
    }

    // Extract key
    z_view_string_t key_string;
    z_keyexpr_as_view_string(z_sample_keyexpr(sample), &key_string);

    // Extract payload
    z_owned_string_t payload_string;
    if (z_bytes_to_string(z_sample_payload(sample), &payload_string) < 0)
    {
        printf("Failed to extract payload\n");
        return;
    }

    // Get sample kind
    const char *kind = kind_to_str(z_sample_kind(sample));

    // Extract attachment if exists
    const z_loaned_bytes_t *attachment = z_sample_attachment(sample);
    char *attachment_str = NULL;
    z_owned_string_t attachment_string;

    if (attachment != NULL && z_bytes_check(attachment))
    {
        if (z_bytes_to_string(attachment, &attachment_string) >= 0)
        {
            size_t att_len = z_string_len(z_loan(attachment_string));
            attachment_str = (char *)malloc(att_len + 1);
            if (attachment_str)
            {
                memcpy(attachment_str, z_string_data(z_loan(attachment_string)), att_len);
                attachment_str[att_len] = '\0';
            }
        }
    }

    // Create null-terminated strings for callback
    size_t key_len = z_string_len(z_loan(key_string));
    size_t payload_len = z_string_len(z_loan(payload_string));

    char *key_buf = (char *)malloc(key_len + 1);
    char *payload_buf = (char *)malloc(payload_len + 1);

    if (key_buf && payload_buf)
    {
        memcpy(key_buf, z_string_data(z_loan(key_string)), key_len);
        key_buf[key_len] = '\0';

        memcpy(payload_buf, z_string_data(z_loan(payload_string)), payload_len);
        payload_buf[payload_len] = '\0';

        printf("Calling callback for subscriber %d - Key: %s, Value: %s, Kind: %s\n",
               subscriber_id, key_buf, payload_buf, kind);

        // Call the Flutter callback with subscriber ID
        sub->callback(key_buf, payload_buf, kind, attachment_str ? attachment_str : "", subscriber_id);

        free(key_buf);
        free(payload_buf);
    }

    // Cleanup
    if (attachment_str != NULL)
    {
        free(attachment_str);
    }
    if (attachment != NULL && z_bytes_len(attachment) > 0)
    {
        z_drop(z_move(attachment_string));
    }
    z_drop(z_move(payload_string));
}



// FIXED MULTIPLE SUBSCRIBER IMPLEMENTATION
FFI_PLUGIN_EXPORT int zenoh_subscribe(const char *key_expr, SubscriberCallback callback)
{
    if (!session_opened) {
        printf("Session not opened\n");
        return -1;
    }

    if (key_expr == NULL || callback == NULL) {
        printf("Invalid arguments\n");
        return -3;
    }

    // Find free slot
    int slot_index = find_free_subscriber_slot();
    if (slot_index == -1) {
        printf("No free subscriber slots available\n");
        return -6;
    }

    printf("Setting up subscriber for: %s in slot %d\n", key_expr, slot_index);

    // Initialize subscriber slot
    subscriber_t* sub = &g_subscribers[slot_index];
    sub->id = g_next_subscriber_id++;
    sub->callback = callback;
    sub->active = true;
    strncpy(sub->key_expr, key_expr, sizeof(sub->key_expr) - 1);

    // Create key expression
    z_view_keyexpr_t keyexpr;
    if (z_view_keyexpr_from_str(&keyexpr, key_expr) < 0) {
        printf("Invalid key expression: %s\n", key_expr);
        sub->active = false;
        return -4;
    }

    // Allocate memory for subscriber ID to pass to callback
    int* subscriber_id_ptr = (int*)malloc(sizeof(int));
    *subscriber_id_ptr = sub->id;

    // Create closure for the callback
    z_owned_closure_sample_t closure;
    z_closure_sample(&closure, data_handler, NULL, subscriber_id_ptr);

    // Declare subscriber
    z_subscriber_options_t sub_options;
    z_subscriber_options_default(&sub_options);
    
    if (z_declare_subscriber(z_loan(session), &sub->subscriber, z_loan(keyexpr), z_move(closure), &sub_options) < 0) {
        printf("Unable to declare subscriber for key: %s\n", key_expr);
        sub->active = false;
        free(subscriber_id_ptr);
        return -5;
    }

    printf("Subscriber successfully declared on '%s' with ID: %d\n", key_expr, sub->id);
    return sub->id; // Return subscriber ID
}

// Unsubscribe specific subscriber
FFI_PLUGIN_EXPORT void zenoh_unsubscribe(int subscriber_id)
{
    subscriber_t* sub = find_subscriber_by_id(subscriber_id);
    if (sub != NULL && sub->active) {
        z_drop(z_move(sub->subscriber));
        sub->active = false;
        sub->callback = NULL;
        printf("Subscriber %d closed for key: %s\n", subscriber_id, sub->key_expr);
    } else {
        printf("Subscriber %d not found or already inactive\n", subscriber_id);
    }
}

// Unsubscribe all subscribers
FFI_PLUGIN_EXPORT void zenoh_unsubscribe_all()
{
    for (int i = 0; i < MAX_SUBSCRIBERS; i++) {
        if (g_subscribers[i].active) {
            z_drop(z_move(g_subscribers[i].subscriber));
            g_subscribers[i].active = false;
            g_subscribers[i].callback = NULL;
        }
    }
    printf("All subscribers closed\n");
}

// Initialize subscribers array
__attribute__((constructor))
static void initialize_subscribers() {
    for (int i = 0; i < MAX_SUBSCRIBERS; i++) {
        g_subscribers[i].active = false;
        g_subscribers[i].callback = NULL;
        g_subscribers[i].id = -1;
        g_subscribers[i].key_expr[0] = '\0';
    }
}