#ifndef _FBUFFER_H_
#define _FBUFFER_H_

#include "ruby.h"
#include "ruby/encoding.h"

/* shims */
/* This is the fallback definition from Ruby 3.4 */

#ifndef RBIMPL_STDBOOL_H
#if defined(__cplusplus)
# if defined(HAVE_STDBOOL_H) && (__cplusplus >= 201103L)
#  include <cstdbool>
# endif
#elif defined(HAVE_STDBOOL_H)
# include <stdbool.h>
#elif !defined(HAVE__BOOL)
typedef unsigned char _Bool;
# define bool  _Bool
# define true  ((_Bool)+1)
# define false ((_Bool)+0)
# define __bool_true_false_are_defined
#endif
#endif

#ifndef RB_UNLIKELY
#define RB_UNLIKELY(expr) expr
#endif

#ifndef RB_LIKELY
#define RB_LIKELY(expr) expr
#endif

#ifndef MAYBE_UNUSED
# define MAYBE_UNUSED(x) x
#endif

enum fbuffer_type {
    FBUFFER_HEAP_ALLOCATED = 0,
    FBUFFER_STACK_ALLOCATED = 1,
};

typedef struct FBufferStruct {
    enum fbuffer_type type;
    unsigned long initial_length;
    unsigned long len;
    unsigned long capa;
    char *ptr;
    VALUE io;
} FBuffer;

#define FBUFFER_STACK_SIZE 512
#define FBUFFER_IO_BUFFER_SIZE (16384 - 1)
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
static VALUE fbuffer_finalize(FBuffer *fb);
#endif

static void fbuffer_stack_init(FBuffer *fb, unsigned long initial_length, char *stack_buffer, long stack_buffer_size)
{
    fb->initial_length = (initial_length > 0) ? initial_length : FBUFFER_INITIAL_LENGTH_DEFAULT;
    if (stack_buffer) {
        fb->type = FBUFFER_STACK_ALLOCATED;
        fb->ptr = stack_buffer;
        fb->capa = stack_buffer_size;
    }
}

static void fbuffer_free(FBuffer *fb)
{
    if (fb->ptr && fb->type == FBUFFER_HEAP_ALLOCATED) {
        ruby_xfree(fb->ptr);
    }
}

static void fbuffer_clear(FBuffer *fb)
{
    fb->len = 0;
}

static void fbuffer_flush(FBuffer *fb)
{
    rb_io_write(fb->io, rb_utf8_str_new(fb->ptr, fb->len));
    fbuffer_clear(fb);
}

static void fbuffer_realloc(FBuffer *fb, unsigned long required)
{
    if (required > fb->capa) {
        if (fb->type == FBUFFER_STACK_ALLOCATED) {
            const char *old_buffer = fb->ptr;
            fb->ptr = ALLOC_N(char, required);
            fb->type = FBUFFER_HEAP_ALLOCATED;
            MEMCPY(fb->ptr, old_buffer, char, fb->len);
        } else {
            REALLOC_N(fb->ptr, char, required);
        }
        fb->capa = required;
    }
}

static void fbuffer_do_inc_capa(FBuffer *fb, unsigned long requested)
{
    if (RB_UNLIKELY(fb->io)) {
        if (fb->capa < FBUFFER_IO_BUFFER_SIZE) {
            fbuffer_realloc(fb, FBUFFER_IO_BUFFER_SIZE);
        } else {
            fbuffer_flush(fb);
        }

        if (RB_LIKELY(requested < fb->capa)) {
            return;
        }
    }

    unsigned long required;

    if (RB_UNLIKELY(!fb->ptr)) {
        fb->ptr = ALLOC_N(char, fb->initial_length);
        fb->capa = fb->initial_length;
    }

    for (required = fb->capa; requested > required - fb->len; required <<= 1);

    fbuffer_realloc(fb, required);
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

static VALUE fbuffer_finalize(FBuffer *fb)
{
    if (fb->io) {
        fbuffer_flush(fb);
        fbuffer_free(fb);
        rb_io_flush(fb->io);
        return fb->io;
    } else {
        VALUE result = rb_utf8_str_new(FBUFFER_PTR(fb), FBUFFER_LEN(fb));
        fbuffer_free(fb);
        return result;
    }
}
#endif
#endif
