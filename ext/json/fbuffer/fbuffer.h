#ifndef _FBUFFER_H_
#define _FBUFFER_H_

#include "ruby.h"
#include "ruby/encoding.h"

enum fbuffer_type {
    HEAP = 0,
    STACK = 1,
};

typedef struct FBufferStruct {
    enum fbuffer_type type;
    unsigned long initial_length;
    unsigned long len;
    unsigned long capa;
    char *ptr;
} FBuffer;

#define FBUFFER_STACK_SIZE 512
#define FBUFFER_INITIAL_LENGTH_DEFAULT 1024

#define FBUFFER_PTR(fb) ((fb)->ptr)
#define FBUFFER_LEN(fb) ((fb)->len)
#define FBUFFER_CAPA(fb) ((fb)->capa)
#define FBUFFER_PAIR(fb) FBUFFER_PTR(fb), FBUFFER_LEN(fb)

static void fbuffer_free(FBuffer *fb);
#ifndef JSON_GENERATOR
static void fbuffer_clear(FBuffer *fb);
#endif
static void fbuffer_append(FBuffer *fb, const char *newstr, unsigned long len);
#ifdef JSON_GENERATOR
static void fbuffer_append_long(FBuffer *fb, long number);
#endif
static inline void fbuffer_append_char(FBuffer *fb, char newchr);
#ifdef JSON_GENERATOR
static VALUE fbuffer_to_s(FBuffer *fb);
#endif

#ifndef RB_UNLIKELY
#define RB_UNLIKELY(expr) expr
#endif

#ifndef RB_LIKELY
#define RB_LIKELY(expr) expr
#endif

static void fbuffer_stack_init(FBuffer *fb, unsigned long initial_length, char *stack_buffer, long stack_buffer_size)
{
    fb->initial_length = (initial_length > 0) ? initial_length : FBUFFER_INITIAL_LENGTH_DEFAULT;
    if (stack_buffer) {
        fb->type = STACK;
        fb->ptr = stack_buffer;
        fb->capa = stack_buffer_size;
    }
}

static void fbuffer_free(FBuffer *fb)
{
    if (fb->ptr && fb->type == HEAP) {
        ruby_xfree(fb->ptr);
    }
}

#ifndef JSON_GENERATOR
static void fbuffer_clear(FBuffer *fb)
{
    fb->len = 0;
}
#endif

static void fbuffer_do_inc_capa(FBuffer *fb, unsigned long requested)
{
    unsigned long required;

    if (RB_UNLIKELY(!fb->ptr)) {
        fb->ptr = ALLOC_N(char, fb->initial_length);
        fb->capa = fb->initial_length;
    }

    for (required = fb->capa; requested > required - fb->len; required <<= 1);

    if (required > fb->capa) {
        if (fb->type == STACK) {
            const char *old_buffer = fb->ptr;
            fb->ptr = ALLOC_N(char, required);
            fb->type = HEAP;
            MEMCPY(fb->ptr, old_buffer, char, fb->len);
        } else {
            REALLOC_N(fb->ptr, char, required);
        }
        fb->capa = required;
    }
}

static inline void fbuffer_inc_capa(FBuffer *fb, unsigned long requested)
{
    if (RB_UNLIKELY(requested > fb->capa - fb->len)) {
        fbuffer_do_inc_capa(fb, requested);
    }
}

static void fbuffer_append(FBuffer *fb, const char *newstr, unsigned long len)
{
    if (len > 0) {
        fbuffer_inc_capa(fb, len);
        MEMCPY(fb->ptr + fb->len, newstr, char, len);
        fb->len += len;
    }
}

#ifdef JSON_GENERATOR
static void fbuffer_append_str(FBuffer *fb, VALUE str)
{
    const char *newstr = StringValuePtr(str);
    unsigned long len = RSTRING_LEN(str);

    RB_GC_GUARD(str);

    fbuffer_append(fb, newstr, len);
}
#endif

static inline void fbuffer_append_char(FBuffer *fb, char newchr)
{
    fbuffer_inc_capa(fb, 1);
    *(fb->ptr + fb->len) = newchr;
    fb->len++;
}

#ifdef JSON_GENERATOR
static long fltoa(long number, char *buf)
{
    static const char digits[] = "0123456789";
    long sign = number;
    char* tmp = buf;

    if (sign < 0) number = -number;
    do *tmp-- = digits[number % 10]; while (number /= 10);
    if (sign < 0) *tmp-- = '-';
    return buf - tmp;
}

#define LONG_BUFFER_SIZE 20
static void fbuffer_append_long(FBuffer *fb, long number)
{
    char buf[LONG_BUFFER_SIZE];
    char *buffer_end = buf + LONG_BUFFER_SIZE;
    long len = fltoa(number, buffer_end - 1);
    fbuffer_append(fb, buffer_end - len, len);
}

static VALUE fbuffer_to_s(FBuffer *fb)
{
    VALUE result = rb_utf8_str_new(FBUFFER_PTR(fb), FBUFFER_LEN(fb));
    fbuffer_free(fb);
    return result;
}
#endif
#endif
