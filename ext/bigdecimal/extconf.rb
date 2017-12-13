# frozen_string_literal: false
require 'mkmf'

case
when File.file?(File.expand_path('../bigdecimal.gemspec', __FILE__))
  gemspec_path = File.expand_path('../bigdecimal.gemspec', __FILE__)
when File.file?(File.expand_path('../../../bigdecimal.gemspec', __FILE__))
  gemspec_path = File.expand_path('../../../bigdecimal.gemspec', __FILE__)
else
  $stderr.puts "Unable to find bigdecimal.gemspec"
  abort
end

bigdecimal_version =
  IO.readlines(gemspec_path)
    .grep(/\Abigdecimal_version\s+=\s+/)[0][/\'([\d\.]+)\'/, 1]

$defs << %Q[-DRUBY_BIGDECIMAL_VERSION=\\"#{bigdecimal_version}\\"]

alias __have_macro__ have_macro

have_func("labs", "stdlib.h")
have_func("llabs", "stdlib.h")
have_func("finite", "math.h")
have_func("isfinite", "math.h")

have_type("struct RRational", "ruby.h")
have_func("rb_rational_num", "ruby.h")
have_func("rb_rational_den", "ruby.h")
have_func("rb_array_const_ptr", "ruby.h")
have_func("rb_sym2str", "ruby.h")

create_makefile('bigdecimal')
