#ifndef RUBY_VERSION_H                               /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_VERSION_H 1
/**
 * @file
 * @author     $Author$
 * @date       Wed May 13 12:56:56 JST 2009
 * @copyright  Copyright (C) 1993-2009 Yukihiro Matsumoto
 * @copyright  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
 * @copyright  Copyright (C) 2000  Information-technology Promotion Agency, Japan
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 *
 * This file contains only
 * - never-changeable information, and
 * - interfaces accessible from extension libraries.
 *
 * Never try to check RUBY_VERSION_CODE etc in extension libraries,
 * check the features with mkmf.rb instead.
 */

/* The origin. */
#define RUBY_AUTHOR "Yukihiro Matsumoto"
#define RUBY_BIRTH_YEAR 1993
#define RUBY_BIRTH_MONTH 2
#define RUBY_BIRTH_DAY 24

/* API version */
#define RUBY_API_VERSION_MAJOR 3
#define RUBY_API_VERSION_MINOR 0
#define RUBY_API_VERSION_TEENY 0
#define RUBY_API_VERSION_CODE (RUBY_API_VERSION_MAJOR*10000+RUBY_API_VERSION_MINOR*100+RUBY_API_VERSION_TEENY)

#ifdef RUBY_EXTERN
/* Internal note: this file could be included from verconf.mk _before_
 * generating config.h, on Windows.  The #ifdef above is to trick such
 * situation. */
RBIMPL_SYMBOL_EXPORT_BEGIN()

/*
 * Interfaces from extension libraries.
 *
 * Before using these infos, think thrice whether they are really
 * necessary or not, and if the answer was yes, think twice a week
 * later again.
 */
RUBY_EXTERN const int ruby_api_version[3];
RUBY_EXTERN const char ruby_version[];
RUBY_EXTERN const char ruby_release_date[];
RUBY_EXTERN const char ruby_platform[];
RUBY_EXTERN const int  ruby_patchlevel;
RUBY_EXTERN const char ruby_description[];
RUBY_EXTERN const char ruby_copyright[];
RUBY_EXTERN const char ruby_engine[];

RBIMPL_SYMBOL_EXPORT_END()
#endif

#endif
