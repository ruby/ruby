/******************************************************************************
 Copyright 2012 Google Inc. All Rights Reserved.
 Author: yugui@google.com (Yugui Sonoda)
 ******************************************************************************/

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <pthread.h>
#include "ppapi/c/pp_errors.h"
#include "ppapi/c/pp_module.h"
#include "ppapi/c/pp_var.h"
#include "ppapi/c/ppb.h"
#include "ppapi/c/ppb_core.h"
#include "ppapi/c/ppb_file_ref.h"
#include "ppapi/c/ppb_instance.h"
#include "ppapi/c/ppb_messaging.h"
#include "ppapi/c/ppb_url_loader.h"
#include "ppapi/c/ppb_url_request_info.h"
#include "ppapi/c/ppb_url_response_info.h"
#include "ppapi/c/ppb_var.h"
#include "ppapi/c/ppp.h"
#include "ppapi/c/ppp_instance.h"
#include "ppapi/c/ppp_messaging.h"

#include "verconf.h"
#include "ruby/ruby.h"
#include "version.h"
#include "gc.h"

#ifdef HAVE_STRUCT_PPB_CORE
typedef struct PPB_Core PPB_Core;
#endif
#ifdef HAVE_STRUCT_PPB_MESSAGING
typedef struct PPB_Messaging PPB_Messaging;
#endif
#ifdef HAVE_STRUCT_PPB_VAR
typedef struct PPB_Var PPB_Var;
#endif
#ifdef HAVE_STRUCT_PPB_URLLOADER
typedef struct PPB_URLLoader PPB_URLLoader;
#endif
#ifdef HAVE_STRUCT_PPB_URLREQUESTINFO
typedef struct PPB_URLRequestInfo PPB_URLRequestInfo;
#endif
#ifdef HAVE_STRUCT_PPB_URLRESPONSEINFO
typedef struct PPB_URLResponseInfo PPB_URLResponseInfo;
#endif
#ifdef HAVE_STRUCT_PPP_INSTANCE
typedef struct PPP_Instance PPP_Instance;
#endif

static PP_Module module_id = 0;
static PPB_Core* core_interface = NULL;
static PPB_Messaging* messaging_interface = NULL;
static PPB_Var* var_interface = NULL;
static PPB_URLLoader* loader_interface = NULL;
static PPB_URLRequestInfo* request_interface = NULL;
static PPB_URLResponseInfo* response_interface = NULL;
static PPB_FileRef* fileref_interface = NULL;
static struct st_table* instance_data = NULL;

static VALUE instance_table = Qundef;

static PP_Instance current_instance = 0;

/******************************************************************************
 * State of instance
 ******************************************************************************/

static void inst_mark(void *const ptr);
static void inst_free(void *const ptr);
static size_t inst_memsize(void *const ptr);
static const rb_data_type_t pepper_instance_data_type = {
  "PepperInstance",
  { inst_mark, inst_free, inst_memsize }
};

struct PepperInstance {
  PP_Instance instance;
  PP_Resource url_loader;
  VALUE self;
  void* async_call_args;
  union {
    int32_t as_int;
    const char* as_str;
    VALUE as_value;
  } async_call_result;
  char buf[1000];

  pthread_t th;
  pthread_mutex_t mutex;
  pthread_cond_t cond;
};

struct PepperInstance*
pruby_get_instance(PP_Instance instance)
{
  VALUE self = rb_hash_aref(instance_table, INT2FIX(instance));
  if (RTEST(self)) {
    struct PepperInstance *inst;
    TypedData_Get_Struct(self, struct PepperInstance, &pepper_instance_data_type, inst);
    return inst;
  }
  else {
    return NULL;
  }
}

#define GET_PEPPER_INSTANCE() (pruby_get_instance(current_instance))

struct PepperInstance*
pruby_register_instance(PP_Instance instance)
{
  VALUE obj;
  struct PepperInstance *data;
  obj = TypedData_Make_Struct(rb_cData, struct PepperInstance, &pepper_instance_data_type, data);
  data->self = obj;
  data->instance = instance;
  data->url_loader = 0;

  pthread_mutex_init(&data->mutex, NULL);
  pthread_cond_init(&data->cond, NULL);

  rb_hash_aset(instance_table, INT2FIX(instance), obj);
  return data;
}

int
pruby_unregister_instance(PP_Instance instance)
{
  VALUE inst = rb_hash_delete(instance_table, INT2FIX(instance));
  return RTEST(inst);
}

static void
inst_mark(void *const ptr)
{
  RUBY_MARK_ENTER("PepperInstance"0);
  if (ptr) {
    const struct PepperInstance* inst = (struct PepperInstance*)ptr;
    RUBY_MARK_UNLESS_NULL(inst->async_call_result.as_value);
  }
  RUBY_MARK_LEAVE("PepperInstance"0);
}

static void
inst_free(void *const ptr)
{
  ruby_xfree(ptr);
}

static size_t
inst_memsize(void *const ptr)
{
  if (ptr) {
    const struct PepperInstance* inst = (struct PepperInstance*)ptr;
    return sizeof(*inst);
  } else {
    return 0;
  }
}

void
pruby_async_return_int(void* data, int32_t result)
{
  /* PPAPI main thread */
  struct PepperInstance* const instance = (struct PepperInstance*)data;
  instance->async_call_result.as_int = result;
  if (pthread_cond_signal(&instance->cond)) {
    perror("pepper-ruby:pthread_cond_signal");
  }
}

void
pruby_async_return_str(void* data, const char *result)
{
  /* PPAPI main thread */
  struct PepperInstance* const instance = (struct PepperInstance*)data;
  instance->async_call_result.as_str = result;
  if (pthread_cond_signal(&instance->cond)) {
    perror("pepper-ruby:pthread_cond_signal");
  }
}

void
pruby_async_return_value(void* data, VALUE value)
{
  /* PPAPI main thread */
  struct PepperInstance* const instance = (struct PepperInstance*)data;
  instance->async_call_result.as_value = value;
  if (pthread_cond_signal(&instance->cond)) {
    perror("pepper-ruby:pthread_cond_signal");
  }
}
/******************************************************************************
 * Conversion between Ruby's VALUE, Pepper's Var and C string
 ******************************************************************************/

/**
 * Creates a new string PP_Var from C string. The resulting object will be a
 * refcounted string object. It will be AddRef()ed for the caller. When the
 * caller is done with it, it should be Release()d.
 * @param[in] str C string to be converted to PP_Var
 * @return PP_Var containing string.
 */
static struct PP_Var
pruby_cstr_to_var(const char* str)
{
#ifdef PPB_VAR_INTERFACE_1_0
  if (var_interface != NULL)
    return var_interface->VarFromUtf8(module_id, str, strlen(str));
  return PP_MakeUndefined();
#else
  return var_interface->VarFromUtf8(str, strlen(str));
#endif
}

/**
 * Returns a mutable C string contained in the @a var or NULL if @a var is not
 * string.  This makes a copy of the string in the @a var and adds a NULL
 * terminator.  Note that VarToUtf8() does not guarantee the NULL terminator on
 * the returned string.  See the comments for VarToUtf8() in ppapi/c/ppb_var.h
 * for more info.  The caller is responsible for freeing the returned memory.
 * @param[in] var PP_Var containing string.
 * @return a mutable C string representation of @a var.
 * @note The caller is responsible for freeing the returned string.
 */
static char*
pruby_var_to_cstr(struct PP_Var var)
{
  uint32_t len = 0;
  if (var_interface != NULL) {
    const char* var_c_str = var_interface->VarToUtf8(var, &len);
    if (len > 0) {
      char* c_str = (char*)malloc(len + 1);
      memcpy(c_str, var_c_str, len);
      c_str[len] = '\0';
      return c_str;
    }
  }
  return NULL;
}

static struct PP_Var
pruby_str_to_var(volatile VALUE str)
{
  if (!RB_TYPE_P(str, T_STRING)) {
    fprintf(stderr, "[BUG] Unexpected object type: %x\n", TYPE(str));
    exit(EXIT_FAILURE);
  }
#ifdef PPB_VAR_INTERFACE_1_0
  if (var_interface != NULL) {
    return var_interface->VarFromUtf8(module_id, RSTRING_PTR(str), RSTRING_LEN(str));
  }
#else
  return var_interface->VarFromUtf8(RSTRING_PTR(str), RSTRING_LEN(str));
#endif
  return PP_MakeUndefined();
}

static struct PP_Var
pruby_obj_to_var(volatile VALUE obj)
{
  static const char* const error =
      "throw 'Failed to convert the result to a JavaScript object';";
  int state;
  obj = rb_protect(&rb_obj_as_string, obj, &state);
  if (!state) {
      return pruby_str_to_var(obj);
  }
  else {
      return pruby_cstr_to_var(error);
  }
}

int
pruby_var_equal_to_cstr_p(struct PP_Var lhs, const char* rhs)
{
  uint32_t len = 0;
  if (var_interface == NULL) {
    return 0;
  }
  else {
    const char* const cstr = var_interface->VarToUtf8(lhs, &len);
    return strncmp(cstr, rhs, len) == 0;
  }
}

int
pruby_var_prefixed_p(struct PP_Var var, const char* prefix)
{
  uint32_t len = 0;
  if (var_interface == NULL) {
    return 0;
  }
  else {
    const char* const cstr = var_interface->VarToUtf8(var, &len);
    const size_t prefix_len = strlen(prefix);
    return len >= prefix_len && memcmp(cstr, prefix, len) == 0;
  }
}


/******************************************************************************
 * Messaging
 ******************************************************************************/

/* Posts the given C string as a message.
 * @param data pointer to a NULL-terminated string */
void
pruby_post_cstr(void* data)
{
  /* PPAPI main thread */
  struct PepperInstance* const instance = (struct PepperInstance*)data;
  const char* const msg = (const char*)instance->async_call_args;
  messaging_interface->PostMessage(instance->instance,
                                   pruby_cstr_to_var(msg));
}

/* Posts the given Ruby VALUE as a message.
 * @param data a VALUE casted to void* */
void
pruby_post_value(void* data)
{
  /* PPAPI main thread */
  struct PepperInstance* const instance = (struct PepperInstance*)data;
  volatile VALUE value = (VALUE)instance->async_call_args;
  messaging_interface->PostMessage(instance->instance, pruby_obj_to_var(value));
}



/******************************************************************************
 * Ruby initialization
 ******************************************************************************/

static void
init_loadpath(void)
{
  ruby_incpush("lib/ruby/"RUBY_LIB_VERSION);
  ruby_incpush("lib/ruby/"RUBY_LIB_VERSION"/"RUBY_PLATFORM);
  ruby_incpush(".");
}

static VALUE
init_libraries_internal(VALUE unused)
{
  extern void Init_enc();
  extern void Init_ext();

  init_loadpath();
  Init_enc();
  Init_ext();
  return Qnil;
}

static void*
init_libraries(void* data)
{
  int state;
  struct PepperInstance* const instance = (struct PepperInstance*)data;
  current_instance = instance->instance;

  if (pthread_mutex_lock(&instance->mutex)) {
    perror("pepper-ruby:pthread_mutex_lock");
    return 0;
  }
  rb_protect(&init_libraries_internal, Qnil, &state);
  pthread_mutex_unlock(&instance->mutex);

  if (state) {
    volatile VALUE err = rb_errinfo();
    err = rb_obj_as_string(err);
  } else {
    instance->async_call_args = (void*)"rubyReady";
    core_interface->CallOnMainThread(
        0, PP_MakeCompletionCallback(pruby_post_cstr, instance), 0);
  }
  return NULL;
}

static int
init_libraries_if_necessary(void)
{
  static int initialized = 0;
  if (!initialized) {
    struct PepperInstance* const instance = GET_PEPPER_INSTANCE();
    int err;
    initialized = 1;
    err = pthread_create(&instance->th, NULL, &init_libraries, instance);
    if (err) {
      fprintf(stderr, "pepper_ruby:pthread_create: %s\n", strerror(err));
      exit(EXIT_FAILURE);
    }
    pthread_detach(instance->th);
  }
  return 0;
}

static int
pruby_init(void)
{
  RUBY_INIT_STACK;
  ruby_init();

  instance_table = rb_hash_new();
  rb_gc_register_mark_object(instance_table);

  return 0;
}


/******************************************************************************
 * Ruby evaluation
 ******************************************************************************/

static void*
pruby_eval(void* data)
{
  extern VALUE ruby_eval_string_from_file_protect(const char* src, const char* path, int* state);
  struct PepperInstance* const instance = (struct PepperInstance*)data;
  volatile VALUE src = (VALUE)instance->async_call_args;
  volatile VALUE result = Qnil;
  volatile int state;

  RUBY_INIT_STACK;

  if (pthread_mutex_lock(&instance->mutex)) {
    perror("pepper-ruby:pthread_mutex_lock");
    return 0;
  }
  result = ruby_eval_string_from_file_protect(
      RSTRING_PTR(src), "(pepper-ruby)", &state);
  pthread_mutex_unlock(&instance->mutex);

  if (!state) {
      instance->async_call_args =
          rb_str_concat(rb_usascii_str_new_cstr("return:"),
                        rb_obj_as_string(result));
      core_interface->CallOnMainThread(
          0, PP_MakeCompletionCallback(pruby_post_value, instance), 0);
      return NULL;
  }
  else {
      rb_set_errinfo(Qnil);
      instance->async_call_args =
          rb_str_concat(rb_usascii_str_new_cstr("error:"),
                        rb_obj_as_string(result));
      core_interface->CallOnMainThread(
          0, PP_MakeCompletionCallback(pruby_post_value, instance), 0);
      return NULL;
  }
}


/******************************************************************************
 * Pepper Module callbacks
 ******************************************************************************/

/**
 * Called when the NaCl module is instantiated on the web page. The identifier
 * of the new instance will be passed in as the first argument (this value is
 * generated by the browser and is an opaque handle).  This is called for each
 * instantiation of the NaCl module, which is each time the <embed> tag for
 * this module is encountered.
 *
 * If this function reports a failure (by returning @a PP_FALSE), the NaCl
 * module will be deleted and DidDestroy will be called.
 * @param[in] instance The identifier of the new instance representing this
 *     NaCl module.
 * @param[in] argc The number of arguments contained in @a argn and @a argv.
 * @param[in] argn An array of argument names.  These argument names are
 *     supplied in the <embed> tag, for example:
 *       <embed id="nacl_module" dimensions="2">
 *     will produce two arguments, one named "id" and one named "dimensions".
 * @param[in] argv An array of argument values.  These are the values of the
 *     arguments listed in the <embed> tag.  In the above example, there will
 *     be two elements in this array, "nacl_module" and "2".  The indices of
 *     these values match the indices of the corresponding names in @a argn.
 * @return @a PP_TRUE on success.
 */
static PP_Bool
Instance_DidCreate(PP_Instance instance,
                   uint32_t argc, const char* argn[], const char* argv[])
{
  struct PepperInstance* data = pruby_register_instance(instance);
  current_instance = instance;
  return init_libraries_if_necessary() ? PP_FALSE : PP_TRUE;
}

/**
 * Called when the NaCl module is destroyed. This will always be called,
 * even if DidCreate returned failure. This routine should deallocate any data
 * associated with the instance.
 * @param[in] instance The identifier of the instance representing this NaCl
 *     module.
 */
static void Instance_DidDestroy(PP_Instance instance) {
  struct PepperInstance* data = pruby_get_instance(instance);
  core_interface->ReleaseResource(data->url_loader);
  pruby_unregister_instance(instance);
}

/**
 * Called when the position, the size, or the clip rect of the element in the
 * browser that corresponds to this NaCl module has changed.
 * @param[in] instance The identifier of the instance representing this NaCl
 *     module.
 * @param[in] position The location on the page of this NaCl module. This is
 *     relative to the top left corner of the viewport, which changes as the
 *     page is scrolled.
 * @param[in] clip The visible region of the NaCl module. This is relative to
 *     the top left of the plugin's coordinate system (not the page).  If the
 *     plugin is invisible, @a clip will be (0, 0, 0, 0).
 */
#ifdef PPP_INSTANCE_INTERFACE_1_0
static void
Instance_DidChangeView(PP_Instance instance,
                       const struct PP_Rect* position,
                       const struct PP_Rect* clip)
{
}
#else
static void
Instance_DidChangeView(PP_Instance instance, PP_Resource view_resource)
{
}
#endif

/**
 * Notification that the given NaCl module has gained or lost focus.
 * Having focus means that keyboard events will be sent to the NaCl module
 * represented by @a instance. A NaCl module's default condition is that it
 * will not have focus.
 *
 * Note: clicks on NaCl modules will give focus only if you handle the
 * click event. You signal if you handled it by returning @a true from
 * HandleInputEvent. Otherwise the browser will bubble the event and give
 * focus to the element on the page that actually did end up consuming it.
 * If you're not getting focus, check to make sure you're returning true from
 * the mouse click in HandleInputEvent.
 * @param[in] instance The identifier of the instance representing this NaCl
 *     module.
 * @param[in] has_focus Indicates whether this NaCl module gained or lost
 *     event focus.
 */
static void
Instance_DidChangeFocus(PP_Instance instance, PP_Bool has_focus)
{
}

/**
 * Handler that gets called after a full-frame module is instantiated based on
 * registered MIME types.  This function is not called on NaCl modules.  This
 * function is essentially a place-holder for the required function pointer in
 * the PPP_Instance structure.
 * @param[in] instance The identifier of the instance representing this NaCl
 *     module.
 * @param[in] url_loader A PP_Resource an open PPB_URLLoader instance.
 * @return PP_FALSE.
 */
static PP_Bool
Instance_HandleDocumentLoad(PP_Instance instance, PP_Resource url_loader)
{
  /* NaCl modules do not need to handle the document load function. */
  return PP_FALSE;
}


/**
 * Handler for messages coming in from the browser via postMessage.  The
 * @a var_message can contain anything: a JSON string; a string that encodes
 * method names and arguments; etc.  For example, you could use JSON.stringify
 * in the browser to create a message that contains a method name and some
 * parameters, something like this:
 *   var json_message = JSON.stringify({ "myMethod" : "3.14159" });
 *   nacl_module.postMessage(json_message);
 * On receipt of this message in @a var_message, you could parse the JSON to
 * retrieve the method name, match it to a function call, and then call it with
 * the parameter.
 * @param[in] instance The instance ID.
 * @param[in] message The contents, copied by value, of the message sent from
 *     browser via postMessage.
 */
void
Messaging_HandleMessage(PP_Instance instance, struct PP_Var var_message)
{
  char* const message = pruby_var_to_cstr(var_message);
  size_t message_len = strlen(message);
  current_instance = instance;

  if (strstr(message, "eval:") != NULL) {
    volatile VALUE src;
    struct PepperInstance* const instance_data = GET_PEPPER_INSTANCE();
    int err;
#define EVAL_PREFIX_LEN 5
    src = rb_str_new(message + EVAL_PREFIX_LEN, message_len - EVAL_PREFIX_LEN);
    instance_data->async_call_args = (void*)src;
    err = pthread_create(&instance_data->th, NULL, &pruby_eval, instance_data);
    if (err) {
      fprintf(stderr, "pepper_ruby:pthread_create: %s\n", strerror(err));
      exit(EXIT_FAILURE);
    }
    pthread_detach(instance_data->th);
  }
  free(message);
}

/**
 * Entry points for the module.
 * Initialize instance interface and scriptable object class.
 * @param[in] a_module_id Module ID
 * @param[in] get_browser_interface Pointer to PPB_GetInterface
 * @return PP_OK on success, any other value on failure.
 */
PP_EXPORT int32_t
PPP_InitializeModule(PP_Module a_module_id, PPB_GetInterface get_browser_interface)
{
  module_id = a_module_id;
  core_interface = (PPB_Core*)(get_browser_interface(PPB_CORE_INTERFACE));
  if (core_interface == NULL) return PP_ERROR_NOINTERFACE;

  var_interface = (PPB_Var*)(get_browser_interface(PPB_VAR_INTERFACE));
  if (var_interface == NULL) return PP_ERROR_NOINTERFACE;

  messaging_interface = (PPB_Messaging*)(get_browser_interface(PPB_MESSAGING_INTERFACE));
  if (messaging_interface == NULL) return PP_ERROR_NOINTERFACE;

  loader_interface = (PPB_URLLoader*)(get_browser_interface(PPB_URLLOADER_INTERFACE));
  if (loader_interface == NULL) return PP_ERROR_NOINTERFACE;

  request_interface = (PPB_URLRequestInfo*)(get_browser_interface(PPB_URLREQUESTINFO_INTERFACE));
  if (request_interface == NULL) return PP_ERROR_NOINTERFACE;

  response_interface = (PPB_URLResponseInfo*)(get_browser_interface(PPB_URLRESPONSEINFO_INTERFACE));
  if (response_interface == NULL) return PP_ERROR_NOINTERFACE;

  fileref_interface = (PPB_FileRef*)(get_browser_interface(PPB_FILEREF_INTERFACE));
  if (fileref_interface == NULL) return PP_ERROR_NOINTERFACE;

  return pruby_init() ? PP_ERROR_FAILED : PP_OK;
}

/**
 * Returns an interface pointer for the interface of the given name, or NULL
 * if the interface is not supported.
 * @param[in] interface_name name of the interface
 * @return pointer to the interface
 */
PP_EXPORT const void*
PPP_GetInterface(const char* interface_name)
{
  if (strcmp(interface_name, PPP_INSTANCE_INTERFACE) == 0) {
    static PPP_Instance instance_interface = {
      &Instance_DidCreate,
      &Instance_DidDestroy,
      &Instance_DidChangeView,
      &Instance_DidChangeFocus,
      &Instance_HandleDocumentLoad
    };
    return &instance_interface;
  } else if (strcmp(interface_name, PPP_MESSAGING_INTERFACE) == 0) {
    static PPP_Messaging messaging_interface = {
      &Messaging_HandleMessage
    };
    return &messaging_interface;
  }
  return NULL;
}

/**
 * Called before the plugin module is unloaded.
 */
PP_EXPORT void
PPP_ShutdownModule()
{
  ruby_cleanup(0);
}

/******************************************************************************
 * Overwrites rb_file_load_ok
 ******************************************************************************/

static void
load_ok_internal(void* data, int32_t unused)
{
  /* PPAPI main thread */
  struct PepperInstance* const instance = (struct PepperInstance*)data;
  const char *const path = (const char*)instance->async_call_args;
  PP_Resource req;
  int result;

  instance->url_loader = loader_interface->Create(instance->instance);
  req = request_interface->Create(instance->instance);
  request_interface->SetProperty(
      req, PP_URLREQUESTPROPERTY_METHOD, pruby_cstr_to_var("HEAD"));
  request_interface->SetProperty(
      req, PP_URLREQUESTPROPERTY_URL, pruby_cstr_to_var(path));

  result = loader_interface->Open(
      instance->url_loader, req,
      PP_MakeCompletionCallback(pruby_async_return_int, instance));
  if (result != PP_OK_COMPLETIONPENDING) {
    pruby_async_return_int(instance, result);
  }
}

static void
pruby_file_fetch_check_response(void* data, int32_t unused)
{
  /* PPAPI main thread */
  PP_Resource res;
  struct PepperInstance* const instance = (struct PepperInstance*)data;

  res = loader_interface->GetResponseInfo(instance->url_loader);
  if (res) {
    struct PP_Var status =
        response_interface->GetProperty(res, PP_URLRESPONSEPROPERTY_STATUSCODE);
    if (status.type == PP_VARTYPE_INT32) {
      pruby_async_return_int(instance, status.value.as_int / 100 == 2 ? PP_OK : PP_ERROR_FAILED);
      return;
    }
    else {
      messaging_interface->PostMessage(
          instance->instance, pruby_cstr_to_var("Unexpected type: ResponseInfoInterface::GetProperty"));
    }
  }
  else {
    messaging_interface->PostMessage(
        instance->instance, pruby_cstr_to_var("Failed to open URL: URLLoaderInterface::GetResponseInfo"));
  }
  pruby_async_return_int(instance, PP_ERROR_FAILED);
}


int
rb_file_load_ok(const char *path)
{
  struct PepperInstance* const instance = GET_PEPPER_INSTANCE();
  if (path[0] == '.' && path[1] == '/') path += 2;

  instance->async_call_args = (void*)path;
  core_interface->CallOnMainThread(
      0, PP_MakeCompletionCallback(load_ok_internal, instance), 0);
  if (pthread_cond_wait(&instance->cond, &instance->mutex)) {
    perror("pepper-ruby:pthread_cond_wait");
    return 0;
  }
  if (instance->async_call_result.as_int != PP_OK) {
    fprintf(stderr, "Failed to open URL: %d: %s\n",
            instance->async_call_result.as_int, path);
    return 0;
  }

  core_interface->CallOnMainThread(
      0, PP_MakeCompletionCallback(pruby_file_fetch_check_response, instance), 0);
  if (pthread_cond_wait(&instance->cond, &instance->mutex)) {
    perror("pepper-ruby:pthread_cond_wait");
    return 0;
  }
  return instance->async_call_result.as_int == PP_OK;
}

/******************************************************************************
 * Overwrites rb_load_file
 ******************************************************************************/

static void
load_file_internal(void* data, int32_t unused)
{
  /* PPAPI main thread */
  struct PepperInstance* const instance = (struct PepperInstance*)data;
  const char *const path = (const char*)instance->async_call_args;
  PP_Resource req;
  int result;

  instance->url_loader = loader_interface->Create(instance->instance);
  req = request_interface->Create(instance->instance);
  request_interface->SetProperty(
      req, PP_URLREQUESTPROPERTY_METHOD, pruby_cstr_to_var("GET"));
  request_interface->SetProperty(
      req, PP_URLREQUESTPROPERTY_URL, pruby_cstr_to_var(path));

  result = loader_interface->Open(
      instance->url_loader, req,
      PP_MakeCompletionCallback(pruby_async_return_int, instance));
  if (result != PP_OK_COMPLETIONPENDING) {
    pruby_async_return_int(instance, result);
  }
}

static void
load_file_read_contents_callback(void *data, int result)
{
  struct PepperInstance* const instance = (struct PepperInstance*)data;
  if (result > 0) {
    rb_str_buf_cat(instance->async_call_result.as_value,
                   instance->buf, result);
    loader_interface->ReadResponseBody(
        instance->url_loader, instance->buf, 1000, PP_MakeCompletionCallback(load_file_read_contents_callback, instance));
  }
  else if (result == 0) {
    pruby_async_return_value(data, instance->async_call_result.as_value);
  }
  else {
    pruby_async_return_value(data, INT2FIX(result));
  }
}

static void
load_file_read_contents(void *data, int result)
{
  struct PepperInstance* const instance = (struct PepperInstance*)data;
  instance->async_call_result.as_value = rb_str_new(0, 0);
  loader_interface->ReadResponseBody(
      instance->url_loader, instance->buf, 1000, PP_MakeCompletionCallback(load_file_read_contents_callback, instance));
}

void*
rb_load_file(const char *path)
{
  const char *real_path;
  struct PepperInstance* instance;
  if (path[0] != '.' || path[1] != '/') path += 2;

  instance = GET_PEPPER_INSTANCE();

  instance->async_call_args = (void*)path;
  core_interface->CallOnMainThread(
      0, PP_MakeCompletionCallback(load_file_internal, instance), 0);
  if (pthread_cond_wait(&instance->cond, &instance->mutex)) {
    perror("pepper-ruby:pthread_cond_wait");
    return 0;
  }
  if (instance->async_call_result.as_int != PP_OK) {
    fprintf(stderr, "Failed to open URL: %d: %s\n",
            instance->async_call_result.as_int, path);
    return 0;
  }

  core_interface->CallOnMainThread(
      0, PP_MakeCompletionCallback(pruby_file_fetch_check_response, instance), 0);
  if (pthread_cond_wait(&instance->cond, &instance->mutex)) {
    perror("pepper-ruby:pthread_cond_wait");
    return 0;
  }
  if (instance->async_call_result.as_int != PP_OK) return 0;

  core_interface->CallOnMainThread(
      0, PP_MakeCompletionCallback(load_file_read_contents, instance), 0);
  if (pthread_cond_wait(&instance->cond, &instance->mutex)) {
    perror("pepper-ruby:pthread_cond_wait");
    return 0;
  }
  if (FIXNUM_P(instance->async_call_result.as_value)) {
    return 0;
  }
  else if (RB_TYPE_P(instance->async_call_result.as_value, T_STRING)) {
    VALUE str = instance->async_call_result.as_value;
    extern void* rb_compile_cstr(const char *f, const char *s, int len, int line);
    return rb_compile_cstr(path, RSTRING_PTR(str), RSTRING_LEN(str), 0);
  }
  else {
    return 0;
  }
}
