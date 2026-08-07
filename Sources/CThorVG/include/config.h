#ifndef TVG_CONFIG_H
#define TVG_CONFIG_H

#define THORVG_VERSION_STRING "1.1.0"
#define THORVG_CPU_ENGINE_SUPPORT 1
#define THORVG_SVG_LOADER_SUPPORT 1
#define THORVG_CAPI_BINDING_SUPPORT 1
#define THORVG_FILE_IO_SUPPORT 1
/* threads off for simpler multi-platform SPM builds (esp. watchOS) */
/* #undef THORVG_THREAD_SUPPORT */

#endif
