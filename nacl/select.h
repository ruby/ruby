// Copyright 2012 Google Inc. All Rights Reserved.
// Author: yugui@google.com (Yugui Sonoda)
#ifndef RUBY_NACL_SELECT_H
#define RUBY_NACL_SELECT_H
int select(int num_fds, fd_set *in_fds, fd_set *out_fds,
           fd_set *ex_fds, struct timeval *timeout);
#endif
