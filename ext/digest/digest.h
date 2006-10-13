/************************************************

  digest.h - header file for ruby digest modules

  $Author$
  created at: Fri May 25 08:54:56 JST 2001


  Copyright (C) 2001-2006 Akinori MUSHA

  $RoughId: digest.h,v 1.3 2001/07/13 15:38:27 knu Exp $
  $Id$

************************************************/

#include "ruby.h"

typedef void (*hash_init_func_t)(void *);
typedef void (*hash_update_func_t)(void *, unsigned char *, size_t);
typedef void (*hash_finish_func_t)(void *, unsigned char *);

typedef struct {
    int api_version;
    size_t digest_len;
    size_t block_len;
    size_t ctx_size;
    hash_init_func_t init_func;
    hash_update_func_t update_func;
    hash_finish_func_t finish_func;
} algo_t;
