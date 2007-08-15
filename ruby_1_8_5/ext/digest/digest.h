/************************************************

  digest.c -

  $Author: knu $
  created at: Fri May 25 08:54:56 JST 2001


  Copyright (C) 2001 Akinori MUSHA

  $RoughId: digest.h,v 1.3 2001/07/13 15:38:27 knu Exp $
  $Id: digest.h,v 1.1 2001/07/13 20:06:13 knu Exp $

************************************************/

#include "ruby.h"

typedef void (*hash_init_func_t) _((void *));
typedef void (*hash_update_func_t) _((void *, unsigned char *, size_t));
typedef void (*hash_end_func_t) _((void *, unsigned char *));
typedef void (*hash_final_func_t) _((unsigned char *, void *));
typedef int (*hash_equal_func_t) _((void *, void *));

typedef struct {
    size_t digest_len;
    size_t ctx_size;
    hash_init_func_t init_func;
    hash_update_func_t update_func;
    hash_end_func_t end_func;
    hash_final_func_t final_func;
    hash_equal_func_t equal_func;
} algo_t;
