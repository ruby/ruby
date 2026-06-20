# frozen_string_literal: true
require 'mkmf'

$defs << "-DJSON_DEBUG" if ENV.fetch("JSON_DEBUG", "0") != "0"
$defs << "-DJSON_WORKAROUND_RB_CATCH_BUG" if RUBY_ENGINE == 'truffleruby'

have_func("rb_enc_interned_str", "ruby/encoding.h") # RUBY_VERSION >= 3.0
have_func("rb_str_to_interned_str", "ruby.h") # RUBY_VERSION >= 3.0
have_func("rb_hash_new_capa", "ruby.h") # RUBY_VERSION >= 3.2
have_func("rb_hash_bulk_insert", "ruby.h") # Missing on TruffleRuby
have_func("ruby_xfree_sized", "ruby.h") # RUBY_VERSION >= 4.1

def have_builtin_func(name, check_expr, opt = "", &b)
  checking_for checking_message(name.funcall_style, nil, opt) do
    if try_compile(<<SRC, opt, &b)
int foo;
int main() { #{check_expr}; return 0; }
SRC
      $defs.push(format("-DHAVE_BUILTIN_%s", name.tr_cpp))
      true
    else
      false
    end
  end
end

have_builtin_func("__builtin_clzll", "__builtin_clzll(0)")

if have_header("x86intrin.h")
  have_func("_lzcnt_u64", "x86intrin.h")
end

if have_header("intrin.h")
  have_func("__lzcnt64", "intrin.h")
  have_func("_BitScanReverse64", "intrin.h")
end

if RUBY_ENGINE == "ruby"
  have_const("RUBY_TYPED_EMBEDDABLE", "ruby.h") # RUBY_VERSION >= 3.3
end

append_cflags("-std=c99")

if enable_config('parser-use-simd', default=!ENV["JSON_DISABLE_SIMD"])
  load __dir__ + "/../simd/conf.rb"
end

create_makefile 'json/ext/parser'
