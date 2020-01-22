#define HAVE_ALLOCA 1
#define HAVE_MEMCPY 1
#define HAVE_MEMORY_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#if _MSC_VER >= 1600
#define HAVE_INTTYPES_H 1
#define HAVE_STDINT_H 1
#endif

#define SIZEOF_DOUBLE 8
#if defined(X86_WIN64)
#define SIZEOF_SIZE_T 8
#else
#define SIZEOF_SIZE_T 4
#endif

#define STACK_DIRECTION -1

#define STDC_HEADERS 1

#ifdef LIBFFI_ASM
#define FFI_HIDDEN(name)
#else
#define FFI_HIDDEN
#endif

