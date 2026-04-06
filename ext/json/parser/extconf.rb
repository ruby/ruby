# frozen_string_literal: true
require 'mkmf'

$defs << "-DJSON_DEBUG" if ENV.fetch("JSON_DEBUG", "0") != "0"
have_func("rb_enc_interned_str", "ruby/encoding.h") # RUBY_VERSION >= 3.0
have_func("rb_str_to_interned_str", "ruby.h") # RUBY_VERSION >= 3.0
have_func("rb_hash_new_capa", "ruby.h") # RUBY_VERSION >= 3.2
have_func("rb_hash_bulk_insert", "ruby.h") # Missing on TruffleRuby

if RUBY_ENGINE == "ruby"
  have_const("RUBY_TYPED_EMBEDDABLE", "ruby.h") # RUBY_VERSION >= 3.3
end

append_cflags("-std=c99")

if enable_config('parser-use-simd', default=!ENV["JSON_DISABLE_SIMD"])
  load __dir__ + "/../simd/conf.rb"
end

create_makefile 'json/ext/parser'
