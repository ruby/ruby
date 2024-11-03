# frozen_string_literal: true
require 'mkmf'

have_func("rb_enc_interned_str", "ruby.h") # RUBY_VERSION >= 3.0
have_func("rb_gc_mark_locations") # Missing on TruffleRuby
append_cflags("-std=c99")

create_makefile 'json/ext/parser'
