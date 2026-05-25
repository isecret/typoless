#include "SherpaOnnxBridge.h"

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../Resources/sherpa-onnx/include/sherpa-onnx/c-api/c-api.h"

struct TypolessSherpaRecognizer {
  const SherpaOnnxOfflineRecognizer *recognizer;
};

typedef const char *(*GetVersionFn)(void);
typedef const SherpaOnnxOfflineRecognizer *(*CreateOfflineRecognizerFn)(
    const SherpaOnnxOfflineRecognizerConfig *config);
typedef void (*DestroyOfflineRecognizerFn)(
    const SherpaOnnxOfflineRecognizer *recognizer);
typedef const SherpaOnnxOfflineStream *(*CreateOfflineStreamFn)(
    const SherpaOnnxOfflineRecognizer *recognizer);
typedef void (*DestroyOfflineStreamFn)(const SherpaOnnxOfflineStream *stream);
typedef void (*AcceptWaveformOfflineFn)(const SherpaOnnxOfflineStream *stream,
                                        int32_t sample_rate,
                                        const float *samples, int32_t n);
typedef void (*DecodeOfflineStreamFn)(
    const SherpaOnnxOfflineRecognizer *recognizer,
    const SherpaOnnxOfflineStream *stream);
typedef const SherpaOnnxOfflineRecognizerResult *(*GetOfflineStreamResultFn)(
    const SherpaOnnxOfflineStream *stream);
typedef void (*DestroyOfflineRecognizerResultFn)(
    const SherpaOnnxOfflineRecognizerResult *result);

static void *g_library = NULL;
static GetVersionFn g_get_version = NULL;
static CreateOfflineRecognizerFn g_create_recognizer = NULL;
static DestroyOfflineRecognizerFn g_destroy_recognizer = NULL;
static CreateOfflineStreamFn g_create_stream = NULL;
static DestroyOfflineStreamFn g_destroy_stream = NULL;
static AcceptWaveformOfflineFn g_accept_waveform = NULL;
static DecodeOfflineStreamFn g_decode_stream = NULL;
static GetOfflineStreamResultFn g_get_result = NULL;
static DestroyOfflineRecognizerResultFn g_destroy_result = NULL;

static void set_error(char *error, int32_t error_size, const char *message) {
  if (error == NULL || error_size <= 0) {
    return;
  }
  snprintf(error, (size_t)error_size, "%s", message);
}

static void *load_symbol(const char *name, char *error, int32_t error_size) {
  void *symbol = dlsym(g_library, name);
  if (symbol == NULL) {
    char buffer[512];
    snprintf(buffer, sizeof(buffer), "sherpa-onnx symbol missing: %s", name);
    set_error(error, error_size, buffer);
  }
  return symbol;
}

int32_t TypolessSherpaLoadLibrary(const char *library_path, char *error,
                                  int32_t error_size) {
  if (g_library != NULL) {
    return 1;
  }

  if (library_path == NULL || library_path[0] == '\0') {
    set_error(error, error_size, "sherpa-onnx library path is empty");
    return 0;
  }

  g_library = dlopen(library_path, RTLD_NOW | RTLD_LOCAL);
  if (g_library == NULL) {
    const char *message = dlerror();
    set_error(error, error_size,
              message != NULL ? message : "failed to load sherpa-onnx library");
    return 0;
  }

  g_get_version = (GetVersionFn)load_symbol("SherpaOnnxGetVersionStr", error, error_size);
  g_create_recognizer = (CreateOfflineRecognizerFn)load_symbol(
      "SherpaOnnxCreateOfflineRecognizer", error, error_size);
  g_destroy_recognizer = (DestroyOfflineRecognizerFn)load_symbol(
      "SherpaOnnxDestroyOfflineRecognizer", error, error_size);
  g_create_stream = (CreateOfflineStreamFn)load_symbol(
      "SherpaOnnxCreateOfflineStream", error, error_size);
  g_destroy_stream = (DestroyOfflineStreamFn)load_symbol(
      "SherpaOnnxDestroyOfflineStream", error, error_size);
  g_accept_waveform = (AcceptWaveformOfflineFn)load_symbol(
      "SherpaOnnxAcceptWaveformOffline", error, error_size);
  g_decode_stream = (DecodeOfflineStreamFn)load_symbol(
      "SherpaOnnxDecodeOfflineStream", error, error_size);
  g_get_result = (GetOfflineStreamResultFn)load_symbol(
      "SherpaOnnxGetOfflineStreamResult", error, error_size);
  g_destroy_result = (DestroyOfflineRecognizerResultFn)load_symbol(
      "SherpaOnnxDestroyOfflineRecognizerResult", error, error_size);

  if (g_get_version == NULL || g_create_recognizer == NULL ||
      g_destroy_recognizer == NULL || g_create_stream == NULL ||
      g_destroy_stream == NULL || g_accept_waveform == NULL ||
      g_decode_stream == NULL || g_get_result == NULL ||
      g_destroy_result == NULL) {
    dlclose(g_library);
    g_library = NULL;
    return 0;
  }

  return 1;
}

const char *TypolessSherpaVersion(void) {
  if (g_get_version == NULL) {
    return "";
  }
  return g_get_version();
}

TypolessSherpaRecognizer *TypolessSherpaCreateRecognizer(
    const char *model_path, const char *tokens_path, const char *language,
    int32_t use_itn, int32_t num_threads, char *error, int32_t error_size) {
  if (g_create_recognizer == NULL) {
    set_error(error, error_size, "sherpa-onnx library is not loaded");
    return NULL;
  }

  SherpaOnnxOfflineRecognizerConfig config;
  memset(&config, 0, sizeof(config));
  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;
  config.model_config.sense_voice.model = model_path;
  config.model_config.sense_voice.language = language;
  config.model_config.sense_voice.use_itn = use_itn;
  config.model_config.tokens = tokens_path;
  config.model_config.provider = "cpu";
  config.model_config.num_threads = num_threads > 0 ? num_threads : 2;
  config.decoding_method = "greedy_search";

  const SherpaOnnxOfflineRecognizer *recognizer = g_create_recognizer(&config);
  if (recognizer == NULL) {
    set_error(error, error_size, "failed to create SenseVoice recognizer");
    return NULL;
  }

  TypolessSherpaRecognizer *wrapper =
      (TypolessSherpaRecognizer *)calloc(1, sizeof(TypolessSherpaRecognizer));
  if (wrapper == NULL) {
    g_destroy_recognizer(recognizer);
    set_error(error, error_size, "failed to allocate recognizer wrapper");
    return NULL;
  }
  wrapper->recognizer = recognizer;
  return wrapper;
}

char *TypolessSherpaRecognize(TypolessSherpaRecognizer *recognizer,
                              const float *samples, int32_t sample_count,
                              int32_t sample_rate, char *error,
                              int32_t error_size) {
  if (recognizer == NULL || recognizer->recognizer == NULL) {
    set_error(error, error_size, "SenseVoice recognizer is not initialized");
    return NULL;
  }
  if (samples == NULL || sample_count <= 0) {
    set_error(error, error_size, "audio samples are empty");
    return NULL;
  }

  const SherpaOnnxOfflineStream *stream =
      g_create_stream(recognizer->recognizer);
  if (stream == NULL) {
    set_error(error, error_size, "failed to create SenseVoice stream");
    return NULL;
  }

  g_accept_waveform(stream, sample_rate, samples, sample_count);
  g_decode_stream(recognizer->recognizer, stream);
  const SherpaOnnxOfflineRecognizerResult *result = g_get_result(stream);
  if (result == NULL) {
    g_destroy_stream(stream);
    set_error(error, error_size, "failed to get SenseVoice result");
    return NULL;
  }

  const char *text = result->text != NULL ? result->text : "";
  char *copy = strdup(text);
  g_destroy_result(result);
  g_destroy_stream(stream);

  if (copy == NULL) {
    set_error(error, error_size, "failed to copy SenseVoice result");
    return NULL;
  }
  return copy;
}

void TypolessSherpaDestroyRecognizer(TypolessSherpaRecognizer *recognizer) {
  if (recognizer == NULL) {
    return;
  }
  if (recognizer->recognizer != NULL && g_destroy_recognizer != NULL) {
    g_destroy_recognizer(recognizer->recognizer);
  }
  free(recognizer);
}

void TypolessSherpaFreeString(char *text) {
  free(text);
}
