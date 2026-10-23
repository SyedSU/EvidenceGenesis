/* First-party Godot4.7.2 C ABI inference wrapper. Main-thread calls only. */
#include "gdextension_interface.h"
#include "inference_core.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(void *) == 8,
               "Genesis save adapter requires a 64-bit target");
/* String/StringName are 8-byte opaque types in the pinned float_64 ABI. */
static void *class_name;
static GDExtensionClassLibraryPtr library;
static GDExtensionInterfaceVariantGetType variant_type;
static GDExtensionTypeFromVariantConstructorFunc to_string;
static GDExtensionVariantFromTypeConstructorFunc from_string;
static GDExtensionInterfaceStringToUtf8Chars string_utf8;
static GDExtensionInterfaceStringNameNewWithUtf8Chars name_new;
static GDExtensionInterfaceStringNewWithUtf8Chars string_new;
static GDExtensionPtrDestructor string_destroy, name_destroy;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;

static char *argument_string(GDExtensionConstStringPtr value) {
  GDExtensionInt size = string_utf8(value, NULL, 0);
  if (size < 0 || size > 40000)
    return NULL;
  char *text = malloc((size_t)size + 1);
  if (!text)
    return NULL;
  GDExtensionInt written = string_utf8(value, text, size);
  text[size] = 0;
  if (written != size || strlen(text) != (size_t)size) {
    free(text);
    return NULL;
  }
  return text;
}
static void method_call(void *userdata, GDExtensionClassInstancePtr instance,
                        const GDExtensionConstVariantPtr *args,
                        GDExtensionInt argc, GDExtensionVariantPtr result,
                        GDExtensionCallError *error) {
  (void)userdata;
  (void)instance;
  char *texts[4] = {NULL, NULL, NULL, NULL};
  const char *answer =
      "{\"state\":\"error\",\"error\":\"Invalid native arguments.\"}";
  error->error = GDEXTENSION_CALL_OK;
  if (argc != 4) {
    error->error = argc < 4 ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS
                            : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
    error->expected = 4;
  } else
    for (int i = 0; i < 4; i++) {
      if (variant_type(args[i]) != GDEXTENSION_VARIANT_TYPE_STRING) {
        error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        error->argument = i;
        error->expected = GDEXTENSION_VARIANT_TYPE_STRING;
        break;
      }
      void *text = NULL;
      to_string(&text, (GDExtensionVariantPtr)args[i]);
      texts[i] = argument_string(&text);
      string_destroy(&text);
    }
  if (error->error == GDEXTENSION_CALL_OK)
    answer = genesis_ai_request(texts[0], texts[1], texts[2], texts[3]);
  void *output = NULL;
  string_new(&output, answer);
  from_string(result, &output);
  string_destroy(&output);
  for (int i = 0; i < 4; i++)
    free(texts[i]);
}
static void method_ptrcall(void *userdata, GDExtensionClassInstancePtr instance,
                           const GDExtensionConstTypePtr *args,
                           GDExtensionTypePtr result) {
  (void)userdata;
  (void)instance;
  char *texts[4];
  for (int i = 0; i < 4; i++)
    texts[i] = argument_string(args[i]);
  string_new(result,
             genesis_ai_request(texts[0], texts[1], texts[2], texts[3]));
  for (int i = 0; i < 4; i++)
    free(texts[i]);
}
static void free_instance(void *userdata,
                          GDExtensionClassInstancePtr instance) {
  (void)userdata;
  (void)instance; /* Abstract class has no instances. */
}
static void add_method(void) {
  void *name = NULL, *empty = NULL, *hint = NULL,
       *names[4] = {NULL, NULL, NULL, NULL};
  name_new(&name, "request");
  name_new(&empty, "");
  string_new(&hint, "");
  GDExtensionPropertyInfo return_info = {0}, args[4] = {{0}, {0}, {0}, {0}};
  GDExtensionClassMethodArgumentMetadata metadata[4] = {0, 0, 0, 0};
  return_info.type = GDEXTENSION_VARIANT_TYPE_STRING;
  return_info.name = &empty;
  return_info.class_name = &empty;
  return_info.hint_string = &hint;
  return_info.usage = 6;
  const char *labels[] = {"operation", "first", "second", "third"};
  for (int i = 0; i < 4; i++) {
    name_new(&names[i], labels[i]);
    args[i] = return_info;
    args[i].name = &names[i];
  }
  GDExtensionClassMethodInfo method = {0};
  method.name = &name;
  method.call_func = method_call;
  method.ptrcall_func = method_ptrcall;
  method.method_flags =
      GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_STATIC;
  method.has_return_value = 1;
  method.return_value_info = &return_info;
  method.argument_count = 4;
  method.arguments_info = args;
  method.arguments_metadata = metadata;
  register_method(library, &class_name, &method);
  for (int i = 0; i < 4; i++) {
    name_destroy(&names[i]);
  }
  name_destroy(&name);
  name_destroy(&empty);
  string_destroy(&hint);
}
static void initialize(void *userdata, GDExtensionInitializationLevel level) {
  (void)userdata;
  if (level != GDEXTENSION_INITIALIZATION_SCENE)
    return;
  void *parent = NULL;
  name_new(&class_name, "GenesisLocalInference");
  name_new(&parent, "RefCounted");
  GDExtensionClassCreationInfo6 info = {0};
  /* Internal static API: not an editor-creatable resource/class. */
  info.is_abstract = 1;
  info.is_exposed = 0;
  info.free_instance_func = free_instance;
  register_class(library, &class_name, &parent, &info);
  add_method();
  name_destroy(&parent);
}
static void deinitialize(void *userdata, GDExtensionInitializationLevel level) {
  (void)userdata;
  if (level != GDEXTENSION_INITIALIZATION_SCENE)
    return;
  genesis_ai_request("shutdown", "", "", "");
  unregister_class(library, &class_name);
  name_destroy(&class_name);
}
AI_EXPORT GDExtensionBool genesis_ai_init(
    GDExtensionInterfaceGetProcAddress get, GDExtensionClassLibraryPtr lib,
    GDExtensionInitialization *init) {
#define LOAD(variable, type, label)                                            \
  do {                                                                         \
    GDExtensionInterfaceFunctionPtr raw = get(label);                          \
    _Static_assert(sizeof(variable) == sizeof(raw),                            \
                   "Godot function pointer ABI");                              \
    memcpy(&variable, &raw, sizeof(variable));                                 \
    if (!variable)                                                             \
      return 0;                                                                \
  } while (0)
  LOAD(variant_type, GDExtensionInterfaceVariantGetType, "variant_get_type");
  LOAD(string_utf8, GDExtensionInterfaceStringToUtf8Chars,
       "string_to_utf8_chars");
  LOAD(name_new, GDExtensionInterfaceStringNameNewWithUtf8Chars,
       "string_name_new_with_utf8_chars");
  LOAD(string_new, GDExtensionInterfaceStringNewWithUtf8Chars,
       "string_new_with_utf8_chars");
  LOAD(register_class, GDExtensionInterfaceClassdbRegisterExtensionClass6,
       "classdb_register_extension_class6");
  LOAD(register_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod,
       "classdb_register_extension_class_method");
  LOAD(unregister_class, GDExtensionInterfaceClassdbUnregisterExtensionClass,
       "classdb_unregister_extension_class");
  GDExtensionInterfaceGetVariantToTypeConstructor to_type;
  GDExtensionInterfaceGetVariantFromTypeConstructor from_type;
  GDExtensionInterfaceVariantGetPtrDestructor destructor;
  LOAD(to_type, GDExtensionInterfaceGetVariantToTypeConstructor,
       "get_variant_to_type_constructor");
  LOAD(from_type, GDExtensionInterfaceGetVariantFromTypeConstructor,
       "get_variant_from_type_constructor");
  LOAD(destructor, GDExtensionInterfaceVariantGetPtrDestructor,
       "variant_get_ptr_destructor");
#undef LOAD
  to_string = to_type(GDEXTENSION_VARIANT_TYPE_STRING);
  from_string = from_type(GDEXTENSION_VARIANT_TYPE_STRING);
  string_destroy = destructor(GDEXTENSION_VARIANT_TYPE_STRING);
  name_destroy = destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
  if (!to_string || !from_string || !string_destroy || !name_destroy)
    return 0;
  library = lib;
  init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
  init->userdata = NULL;
  init->initialize = initialize;
  init->deinitialize = deinitialize;
  return 1;
}
