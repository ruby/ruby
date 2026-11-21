#ifndef PSYCH_H
#define PSYCH_H

#include <ruby.h>
#include <ruby/encoding.h>

#ifndef HAVE_RB_LEN_T
typedef long rb_len_t;
#endif

#ifdef PSYCH_USE_LIBFYAML
#include <libfyaml.h>
#else
#include <yaml.h>
#endif

#include <psych_parser.h>
#include <psych_emitter.h>
#include <psych_to_ruby.h>
#include <psych_yaml_tree.h>

extern VALUE mPsych;


#endif
