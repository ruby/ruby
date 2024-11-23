# frozen_string_literal: true
require 'mkmf'

have_func("rb_enc_interned_str", "ruby.h") # RUBY_VERSION >= 3.0
have_func("rb_hash_new_capa", "ruby.h") # RUBY_VERSION >= 3.2
have_func("rb_hash_bulk_insert", "ruby.h") # Missing on TruffleRuby
have_func("rb_category_warn", "ruby.h") # Missing on TruffleRuby

append_cflags("-std=c99")

create_makefile 'json/ext/parser'
