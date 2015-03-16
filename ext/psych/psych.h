#ifndef PSYCH_H
#define PSYCH_H

#include <ruby.h>

#ifdef HAVE_RUBY_ENCODING_H
#include <ruby/encoding.h>
#endif

#include <yaml.h>

#include <psych_parser.h>
#include <psych_emitter.h>
#include <psych_to_ruby.h>
#include <psych_yaml_tree.h>

extern VALUE mPsych;


#endif
