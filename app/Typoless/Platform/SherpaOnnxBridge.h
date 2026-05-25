#ifndef TypolessSherpaOnnxBridge_h
#define TypolessSherpaOnnxBridge_h

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TypolessSherpaRecognizer TypolessSherpaRecognizer;

int32_t TypolessSherpaLoadLibrary(const char *library_path, char *error, int32_t error_size);

const char *TypolessSherpaVersion(void);

TypolessSherpaRecognizer *TypolessSherpaCreateRecognizer(
    const char *model_path,
    const char *tokens_path,
    const char *language,
    int32_t use_itn,
    int32_t num_threads,
    char *error,
    int32_t error_size);

char *TypolessSherpaRecognize(
    TypolessSherpaRecognizer *recognizer,
    const float *samples,
    int32_t sample_count,
    int32_t sample_rate,
    char *error,
    int32_t error_size);

void TypolessSherpaDestroyRecognizer(TypolessSherpaRecognizer *recognizer);

void TypolessSherpaFreeString(char *text);

#ifdef __cplusplus
}
#endif

#endif
