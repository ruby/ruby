/*
 * Copyright 2011 Google Inc. All Rights Reserved.
 * Author: yugui@google.com (Yugui Sonoda)
 * */
#ifndef RUBY_NACL_STAT_H
#define RUBY_NACL_STAT_H
mode_t umask(mode_t mask);
struct stat;
int lstat(const char* path, struct stat* result);
#endif
