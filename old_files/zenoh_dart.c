#include "zenoh_dart.h"

// Helper function to convert sample kind to string
const char *kind_to_str(z_sample_kind_t kind)
{
  switch (kind)
  {
  case Z_SAMPLE_KIND_PUT:
    return "PUT";
  case Z_SAMPLE_KIND_DELETE:
    return "DELETE";
  default:
    return "UNKNOWN";
  }
}

// Find subscriber by ID
static subscriber_node_t *find_subscriber_by_id(int subscriber_id)
{
  pthread_mutex_lock(&g_subscribers_mutex);
  subscriber_node_t *current = g_subscribers_head;
  while (current != NULL)
  {
    if (current->active && current->id == subscriber_id)
    {
      pthread_mutex_unlock(&g_subscribers_mutex);
      return current;
    }
    current = current->next;
  }
  pthread_mutex_unlock(&g_subscribers_mutex);
  return NULL;
}

// Add subscriber to linked list
static int add_subscriber(subscriber_node_t *new_sub)
{
  pthread_mutex_lock(&g_subscribers_mutex);

  // Assign ID
  new_sub->id = g_next_subscriber_id++;
  new_sub->active = true;
  new_sub->next = NULL;

  // Add to head of list
  if (g_subscribers_head == NULL)
  {
    g_subscribers_head = new_sub;
  }
  else
  {
    new_sub->next = g_subscribers_head;
    g_subscribers_head = new_sub;
  }

  int id = new_sub->id;
  pthread_mutex_unlock(&g_subscribers_mutex);
  return id;
}

// Remove subscriber from linked list
static void remove_subscriber(int subscriber_id)
{
  pthread_mutex_lock(&g_subscribers_mutex);

  subscriber_node_t *current = g_subscribers_head;
  subscriber_node_t *prev = NULL;

  while (current != NULL)
  {
    if (current->id == subscriber_id)
    {
      if (prev == NULL)
      {
        // Remove from head
        g_subscribers_head = current->next;
      }
      else
      {
        prev->next = current->next;
      }

      // Free memory
      free(current);
      pthread_mutex_unlock(&g_subscribers_mutex);
      return;
    }

    prev = current;
    current = current->next;
  }

  pthread_mutex_unlock(&g_subscribers_mutex);
}

// Data handler for subscriber - called when data is received
void data_handler(z_loaned_sample_t *sample, void *arg)
{
  int subscriber_id = *(int *)arg;
  subscriber_node_t *sub = find_subscriber_by_id(subscriber_id);

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
  char *attachment_str = ""; // Default to empty string
  z_owned_string_t attachment_string;

  // Create null-terminated strings for callback
  size_t key_len = z_string_len(z_loan(key_string));
  size_t payload_len = z_string_len(z_loan(payload_string));

  char *key_buf = (char *)malloc(key_len + 1);
  char *payload_buf = (char *)malloc(payload_len + 1);
  char *kind_buf = strdup(kind); // Make a copy of kind string too

  if (key_buf && payload_buf && kind_buf)
  {
    memcpy(key_buf, z_string_data(z_loan(key_string)), key_len);
    key_buf[key_len] = '\0';

    memcpy(payload_buf, z_string_data(z_loan(payload_string)), payload_len);
    payload_buf[payload_len] = '\0';

    printf("Calling callback for subscriber %d - Key: %s, Value: %s, Kind: %s\n",
           subscriber_id, key_buf, payload_buf, kind_buf);

    // CRITICAL: Pass ownership to Dart
    // Dart MUST free these strings using zenoh_free_string()
    sub->callback(key_buf, payload_buf, kind_buf, attachment_str, subscriber_id);

    // DO NOT FREE HERE - Dart will free them!
    // The strings are now owned by Dart side
  }
  else
  {
    // Allocation failed - clean up
    if (key_buf)
      free(key_buf);
    if (payload_buf)
      free(payload_buf);
    if (kind_buf)
      free(kind_buf);
  }

  // Cleanup Zenoh owned strings
  if (attachment != NULL && z_bytes_len(attachment) > 0)
  {
    z_drop(z_move(attachment_string));
  }
  z_drop(z_move(payload_string));
}

// Reply callback function for zenoh_get
void reply_callback(z_loaned_reply_t *reply, void *context)
{
  if (z_reply_is_ok(reply))
  {
    const z_loaned_sample_t *sample = z_reply_ok(reply);
    const z_loaned_bytes_t *payload = z_sample_payload(sample);

    if (payload)
    {
      size_t len = z_bytes_len(payload);
      last_received_value = (char *)malloc(len + 1);
      if (last_received_value)
      {
        z_bytes_reader_t reader = z_bytes_get_reader(payload);
        size_t bytes_read = z_bytes_reader_read(&reader, (uint8_t *)last_received_value, len);
        last_received_value[bytes_read] = '\0';
        reply_received = true;
      }
    }
  }
}

// Zenoh-C function implementations
FFI_PLUGIN_EXPORT int zenoh_init()
{
  z_owned_config_t config;

  z_config_default(&config);

  z_owned_session_t s;
  if (z_open(&s, z_move(config), NULL) < 0)
  {
    printf("Failed to open Zenoh session\n");
    return -1;
  }
  z_drop(z_move(s));
  return 0;
}

FFI_PLUGIN_EXPORT void zenoh_cleanup()
{
  zenoh_unsubscribe_all();
  if (session_opened)
  {
    z_drop(z_move(session));
    session_opened = false;
  }
  if (publisher_declared)
  {
    z_drop(z_move(global_publisher));
    publisher_declared = false;
  }
}

FFI_PLUGIN_EXPORT int zenoh_open_session()
{
  if (session_opened)
  {
    return 0;
  }

  z_owned_config_t config;
  z_config_default(&config);

  // zc_config_insert_json5(z_loan(config), Z_CONFIG_CONNECT_KEY,
  //                        "[\"tcp/127.0.0.1:7447\", \"tcp/192.168.0.102:7450\",\"tcp/172.18.0.2:7447\"]");

  // // Desktop: Enable multicast interface
  // zc_config_insert_json5(z_loan(config), Z_CONFIG_MULTICAST_INTERFACE_KEY, "\"auto\"");

  // // Increase scouting timeout for better discovery
  // zc_config_insert_json5(z_loan(config), Z_CONFIG_SCOUTING_TIMEOUT_KEY, "3000");

  if (z_open(&session, z_move(config), NULL) < 0)
  {
    return -1;
  }

  session_opened = true;
  return 0;
}

FFI_PLUGIN_EXPORT void zenoh_close_session()
{
  zenoh_unsubscribe_all();
  if (session_opened)
  {
    z_drop(z_move(session));
    session_opened = false;
  }
}

FFI_PLUGIN_EXPORT int zenoh_put(const char *key, const char *value)
{
  if (!session_opened)
  {
    return -1;
  }

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0)
  {
    return -1;
  }

  z_owned_bytes_t payload;
  z_bytes_copy_from_str(&payload, value);

  z_put_options_t options;
  z_put_options_default(&options);

  if (z_put(z_loan(session), z_loan(keyexpr), z_move(payload), &options) < 0)
  {
    return -1;
  }

  return 0;
}

FFI_PLUGIN_EXPORT int zenoh_publish(const char *key, const char *value)
{
  if (!session_opened)
  {
    return -1;
  }

  if (!publisher_declared || strcmp(current_publisher_key, key) != 0)
  {
    if (publisher_declared)
    {
      z_drop(z_move(global_publisher));
      publisher_declared = false;
    }

    z_view_keyexpr_t keyexpr;
    if (z_view_keyexpr_from_str(&keyexpr, key) < 0)
    {
      return -1;
    }

    z_publisher_options_t pub_options;
    z_publisher_options_default(&pub_options);

    if (z_declare_publisher(z_loan(session), &global_publisher, z_loan(keyexpr), &pub_options) < 0)
    {
      return -1;
    }

    strncpy(current_publisher_key, key, sizeof(current_publisher_key) - 1);
    publisher_declared = true;
  }

  z_owned_bytes_t payload;
  z_bytes_copy_from_str(&payload, value);

  z_publisher_put_options_t put_options;
  z_publisher_put_options_default(&put_options);

  if (z_publisher_put(z_loan(global_publisher), z_move(payload), &put_options) < 0)
  {
    return -1;
  }

  return 0;
}

FFI_PLUGIN_EXPORT char *zenoh_get(const char *key)
{
  if (!session_opened)
  {
    return NULL;
  }

  reply_received = false;
  if (last_received_value)
  {
    free(last_received_value);
    last_received_value = NULL;
  }

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0)
  {
    return NULL;
  }

  z_owned_closure_reply_t closure;
  z_closure_reply(&closure, reply_callback, NULL, NULL);

  z_get_options_t get_options;
  z_get_options_default(&get_options);
  get_options.timeout_ms = 5000;

  z_moved_closure_reply_t moved_closure = {closure};
  if (z_get(z_loan(session), z_loan(keyexpr), "", &moved_closure, &get_options) < 0)
  {
    return NULL;
  }

  int max_wait_ms = 6000;
  int wait_step_ms = 100;

  for (int i = 0; i < max_wait_ms / wait_step_ms; i++)
  {
    if (reply_received)
    {
      break;
    }
#if _WIN32
    Sleep(wait_step_ms);
#else
    usleep(wait_step_ms * 1000);
#endif
  }

  if (reply_received && last_received_value)
  {
    return strdup(last_received_value);
  }

  return NULL;
}

FFI_PLUGIN_EXPORT void zenoh_free_string(char *str)
{
  if (str)
  {
    free(str);
  }
}

FFI_PLUGIN_EXPORT char *zenoh_get_with_handler(const char *key)
{
  if (!session_opened)
  {
    return NULL;
  }

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0)
  {
    return NULL;
  }

  z_owned_fifo_handler_reply_t handler;
  z_owned_closure_reply_t closure;
  z_fifo_channel_reply_new(&closure, &handler, 16);

  z_get_options_t get_options;
  z_get_options_default(&get_options);
  get_options.timeout_ms = 5000;

  z_moved_closure_reply_t moved_closure = {closure};
  if (z_get(z_loan(session), z_loan(keyexpr), "", &moved_closure, &get_options) < 0)
  {
    z_drop(z_move(handler));
    return NULL;
  }

  z_owned_reply_t reply;
  char *result = NULL;

  int max_wait_ms = 6000;
  int wait_step_ms = 100;

  for (int i = 0; i < max_wait_ms / wait_step_ms; i++)
  {
    if (z_fifo_handler_reply_try_recv(z_loan(handler), &reply) == Z_OK)
    {
      if (z_reply_is_ok(z_loan(reply)))
      {
        const z_loaned_sample_t *sample = z_reply_ok(z_loan(reply));
        const z_loaned_bytes_t *payload = z_sample_payload(sample);

        if (payload)
        {
          size_t len = z_bytes_len(payload);
          result = (char *)malloc(len + 1);
          if (result)
          {
            z_bytes_reader_t reader = z_bytes_get_reader(payload);
            size_t bytes_read = z_bytes_reader_read(&reader, (uint8_t *)result, len);
            result[bytes_read] = '\0';
          }
        }
      }
      z_drop(z_move(reply));
      break;
    }
#if _WIN32
    Sleep(wait_step_ms);
#else
    usleep(wait_step_ms * 1000);
#endif
  }

  z_drop(z_move(handler));
  return result;
}

// IMPROVED SUBSCRIBER IMPLEMENTATION WITH LINKED LIST
FFI_PLUGIN_EXPORT int zenoh_subscribe(const char *key_expr, SubscriberCallback callback)
{
  if (!session_opened)
  {
    printf("Session not opened\n");
    return -1;
  }

  if (key_expr == NULL || callback == NULL)
  {
    printf("Invalid arguments\n");
    return -3;
  }

  // Create new subscriber node
  subscriber_node_t *new_sub = (subscriber_node_t *)malloc(sizeof(subscriber_node_t));
  if (new_sub == NULL)
  {
    printf("Memory allocation failed\n");
    return -6;
  }

  printf("Setting up subscriber for: %s\n", key_expr);

  // Initialize subscriber
  new_sub->callback = callback;
  strncpy(new_sub->key_expr, key_expr, sizeof(new_sub->key_expr) - 1);

  // Create key expression
  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key_expr) < 0)
  {
    printf("Invalid key expression: %s\n", key_expr);
    free(new_sub);
    return -4;
  }

  // Allocate memory for subscriber ID to pass to callback
  int *subscriber_id_ptr = (int *)malloc(sizeof(int));
  if (subscriber_id_ptr == NULL)
  {
    printf("Memory allocation failed for subscriber ID\n");
    free(new_sub);
    return -6;
  }

  // Add to linked list and get ID
  int subscriber_id = add_subscriber(new_sub);
  *subscriber_id_ptr = subscriber_id;

  // Create closure for the callback
  z_owned_closure_sample_t closure;
  z_closure_sample(&closure, data_handler, NULL, subscriber_id_ptr);

  // Declare subscriber
  z_subscriber_options_t sub_options;
  z_subscriber_options_default(&sub_options);

  if (z_declare_subscriber(z_loan(session), &new_sub->subscriber, z_loan(keyexpr), z_move(closure), &sub_options) < 0)
  {
    printf("Unable to declare subscriber for key: %s\n", key_expr);
    remove_subscriber(subscriber_id);
    free(subscriber_id_ptr);
    return -5;
  }

  printf("Subscriber successfully declared on '%s' with ID: %d\n", key_expr, subscriber_id);
  return subscriber_id;
}

// Unsubscribe specific subscriber
FFI_PLUGIN_EXPORT void zenoh_unsubscribe(int subscriber_id)
{
  subscriber_node_t *sub = find_subscriber_by_id(subscriber_id);
  if (sub != NULL && sub->active)
  {
    z_drop(z_move(sub->subscriber));
    sub->active = false;
    sub->callback = NULL;
    remove_subscriber(subscriber_id);
    printf("Subscriber %d closed for key: %s\n", subscriber_id, sub->key_expr);
  }
  else
  {
    printf("Subscriber %d not found or already inactive\n", subscriber_id);
  }
}

// Unsubscribe all subscribers
FFI_PLUGIN_EXPORT void zenoh_unsubscribe_all()
{
  pthread_mutex_lock(&g_subscribers_mutex);

  subscriber_node_t *current = g_subscribers_head;
  while (current != NULL)
  {
    subscriber_node_t *next = current->next;
    if (current->active)
    {
      z_drop(z_move(current->subscriber));
      current->active = false;
      current->callback = NULL;
    }
    free(current);
    current = next;
  }

  g_subscribers_head = NULL;
  pthread_mutex_unlock(&g_subscribers_mutex);
  printf("All subscribers closed\n");
}

// Get current subscriber count (useful for debugging)
FFI_PLUGIN_EXPORT int zenoh_get_subscriber_count()
{
  pthread_mutex_lock(&g_subscribers_mutex);
  int count = 0;
  subscriber_node_t *current = g_subscribers_head;
  while (current != NULL)
  {
    if (current->active)
    {
      count++;
    }
    current = current->next;
  }
  pthread_mutex_unlock(&g_subscribers_mutex);
  return count;
}