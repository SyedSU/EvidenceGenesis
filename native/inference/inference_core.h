#pragma once
#ifdef _WIN32
#define AI_EXPORT __declspec(dllexport)
#else
#define AI_EXPORT __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
/* Returned UTF8 JSON is owned by the calling thread until its next call.
   All four arguments must be NUL-terminated strings. No exceptions cross ABI.
 */
AI_EXPORT const char *genesis_ai_request(const char *operation,
                                         const char *first, const char *second,
                                         const char *third);
#ifdef __cplusplus
}
#endif
