// Copyright 2012 Google Inc. All Rights Reserved.
// Author: yugui@google.com (Yugui Sonoda)
#ifndef RUBY_NACL_UNISTD_H
#define RUBY_NACL_UNISTD_H
int seteuid(pid_t pid);
int setegid(pid_t pid);
int truncate(const char* path, off_t new_size);
int ftruncate(int fd, off_t new_size);
#endif
