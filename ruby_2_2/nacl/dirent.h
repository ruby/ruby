/*
 * Copyright 2011 Google Inc. All Rights Reserved.
 * Author: yugui@google.com (Yugui Sonoda)
 */
#ifndef RUBY_NACL_DIRENT_H
#define RUBY_NACL_DIRENT_H

/* NaCl SDK 0.3 has implementations of dir functions but no declaration in
 * dirent.h */
int readdir_r(DIR *dirp, struct dirent *entry, struct dirent **result);
void rewinddir(DIR *dirp);
long telldir(DIR *dirp);
void seekdir(DIR *dirp, long offset);

#endif
