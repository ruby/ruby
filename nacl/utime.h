/*
 * Copyright 2011 Google Inc. All Rights Reserved.
 * Author: yugui@google.com (Yugui Sonoda)
 */

#ifndef RUBY_NACL_UTIME_H
#define RUBY_NACL_UTIME_H
#include <utime.h>
int utime(const char *filename, const struct utimbuf *times);
int utimes(const char *filename, const struct timeval times[2]);
#endif
