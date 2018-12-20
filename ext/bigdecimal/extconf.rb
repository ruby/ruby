# frozen_string_literal: false
require 'mkmf'

gemspec_name = gemspec_path = nil
unless ['', '../../'].any? {|dir|
         gemspec_name = "#{dir}bigdecimal.gemspec"
         gemspec_path = File.expand_path("../#{gemspec_name}", __FILE__)
         File.file?(gemspec_path)
       }
  $stderr.puts "Unable to find bigdecimal.gemspec"
  abort
end

bigdecimal_version =
  IO.readlines(gemspec_path)
    .grep(/\Abigdecimal_version\s+=\s+/)[0][/\'([\d\.]+)\'/, 1]

$defs << %Q[-DRUBY_BIGDECIMAL_VERSION=\\"#{bigdecimal_version}\\"]

have_func("labs", "stdlib.h")
have_func("llabs", "stdlib.h")
have_func("finite", "math.h")
have_func("isfinite", "math.h")

have_type("struct RRational", "ruby.h")
have_func("rb_rational_num", "ruby.h")
have_func("rb_rational_den", "ruby.h")
have_func("rb_array_const_ptr", "ruby.h")
have_func("rb_sym2str", "ruby.h")

if File.file?(File.expand_path('../lib/bigdecimal.rb', __FILE__))
  bigdecimal_rb = "$(srcdir)/lib/bigdecimal.rb"
else
  bigdecimal_rb = "$(srcdir)/../../lib/bigdecimal.rb"
end

create_makefile('bigdecimal') {|mf|
  mf << "GEMSPEC = #{gemspec_name}\n"
  mf << "BIGDECIMAL_RB = #{bigdecimal_rb}\n"
}
