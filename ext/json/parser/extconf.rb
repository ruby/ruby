# frozen_string_literal: true
require 'mkmf'

have_func("rb_enc_raise", "ruby.h")
have_func("rb_enc_interned_str", "ruby.h")

append_cflags("-std=c99")

create_makefile 'json/ext/parser'
