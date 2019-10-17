/**********************************************************************

  loadpath.c -

  $Author$
  created at: Wed May 15 14:19:50 JST 2013

  Copyright (C) 2013 Yukihiro Matsumoto

**********************************************************************/

#include "verconf.h"
#include "ruby/ruby.h"

/* Define RUBY_REVISION to avoid revision.h inclusion via version.h. */
#define RUBY_REVISION 0
#include "version.h"

#ifndef RUBY_ARCH
#define RUBY_ARCH RUBY_PLATFORM
#endif
#ifndef RUBY_SITEARCH
#define RUBY_SITEARCH RUBY_ARCH
#endif
#ifdef RUBY_PLATFORM_CPU
#define RUBY_THINARCH RUBY_PLATFORM_CPU"-"RUBY_PLATFORM_OS
#endif
#ifndef RUBY_LIB_PREFIX
#ifndef RUBY_EXEC_PREFIX
#error RUBY_EXEC_PREFIX must be defined
#endif
#define RUBY_LIB_PREFIX RUBY_EXEC_PREFIX"/lib/ruby"
#endif
#ifndef RUBY_SITE_LIB
#define RUBY_SITE_LIB RUBY_LIB_PREFIX"/site_ruby"
#endif
#ifndef RUBY_VENDOR_LIB
#define RUBY_VENDOR_LIB RUBY_LIB_PREFIX"/vendor_ruby"
#endif

typedef char ruby_lib_version_string[(int)sizeof(RUBY_LIB_VERSION) - 2];

#ifndef RUBY_LIB
#define RUBY_LIB                    RUBY_LIB_PREFIX  "/"RUBY_LIB_VERSION
#endif
#define RUBY_SITE_LIB2              RUBY_SITE_LIB    "/"RUBY_LIB_VERSION
#define RUBY_VENDOR_LIB2            RUBY_VENDOR_LIB  "/"RUBY_LIB_VERSION
#ifndef RUBY_ARCH_LIB_FOR
#define RUBY_ARCH_LIB_FOR(arch)        RUBY_LIB         "/"arch
#endif
#ifndef RUBY_SITE_ARCH_LIB_FOR
#define RUBY_SITE_ARCH_LIB_FOR(arch)   RUBY_SITE_LIB2   "/"arch
#endif
#ifndef RUBY_VENDOR_ARCH_LIB_FOR
#define RUBY_VENDOR_ARCH_LIB_FOR(arch) RUBY_VENDOR_LIB2 "/"arch
#endif

#if !defined(LOAD_RELATIVE) || !LOAD_RELATIVE
const char ruby_exec_prefix[] = RUBY_EXEC_PREFIX;
#endif

const char ruby_initial_load_paths[] =
#ifndef NO_INITIAL_LOAD_PATH
#ifdef RUBY_SEARCH_PATH
    RUBY_SEARCH_PATH "\0"
#endif
#ifndef NO_RUBY_SITE_LIB
    RUBY_SITE_LIB2 "\0"
#ifdef RUBY_THINARCH
    RUBY_SITE_ARCH_LIB_FOR(RUBY_THINARCH) "\0"
#endif
    RUBY_SITE_ARCH_LIB_FOR(RUBY_SITEARCH) "\0"
    RUBY_SITE_LIB "\0"
#endif

#ifndef NO_RUBY_VENDOR_LIB
    RUBY_VENDOR_LIB2 "\0"
#ifdef RUBY_THINARCH
    RUBY_VENDOR_ARCH_LIB_FOR(RUBY_THINARCH) "\0"
#endif
    RUBY_VENDOR_ARCH_LIB_FOR(RUBY_SITEARCH) "\0"
    RUBY_VENDOR_LIB "\0"
#endif

    RUBY_LIB "\0"
#ifdef RUBY_THINARCH
    RUBY_ARCH_LIB_FOR(RUBY_THINARCH) "\0"
#endif
    RUBY_ARCH_LIB_FOR(RUBY_ARCH) "\0"
#endif
    "";
