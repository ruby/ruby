# frozen_string_literal: false
require 'mkmf'

def check_bigdecimal_version(gemspec_path)
  message "checking RUBY_BIGDECIMAL_VERSION... "
  bigdecimal_version = File.read(gemspec_path).match(/^\s*s\.version\s+=\s+['"]([^'"]+)['"]\s*$/)[1]

  version_components = bigdecimal_version.split('.')
  bigdecimal_version = version_components[0, 3].join('.')
  bigdecimal_version << "-#{version_components[3]}" if version_components[3]
  $defs << %Q[-DRUBY_BIGDECIMAL_VERSION=\\"#{bigdecimal_version}\\"]

  message "#{bigdecimal_version}\n"
end

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

gemspec_name = gemspec_path = nil
unless ['', '../../'].any? {|dir|
         gemspec_name = "#{dir}bigdecimal.gemspec"
         gemspec_path = File.expand_path("../#{gemspec_name}", __FILE__)
         File.file?(gemspec_path)
       }
  $stderr.puts "Unable to find bigdecimal.gemspec"
  abort
end

check_bigdecimal_version(gemspec_path)

have_builtin_func("__builtin_clz", "__builtin_clz(0)")
have_builtin_func("__builtin_clzl", "__builtin_clzl(0)")
have_builtin_func("__builtin_clzll", "__builtin_clzll(0)")

have_header("float.h")
have_header("math.h")
have_header("stdbool.h")
have_header("stdlib.h")

have_header("x86intrin.h")
have_func("_lzcnt_u32", "x86intrin.h")
have_func("_lzcnt_u64", "x86intrin.h")

have_header("intrin.h")
have_func("__lzcnt", "intrin.h")
have_func("__lzcnt64", "intrin.h")
have_func("_BitScanReverse", "intrin.h")
have_func("_BitScanReverse64", "intrin.h")

have_func("labs", "stdlib.h")
have_func("llabs", "stdlib.h")
have_func("finite", "math.h")
have_func("isfinite", "math.h")

have_header("ruby/atomic.h")
have_header("ruby/internal/has/builtin.h")
have_header("ruby/internal/static_assert.h")

have_type("struct RRational", "ruby.h")
have_func("rb_rational_num", "ruby.h")
have_func("rb_rational_den", "ruby.h")
have_type("struct RComplex", "ruby.h")
have_func("rb_complex_real", "ruby.h")
have_func("rb_complex_imag", "ruby.h")
have_func("rb_array_const_ptr", "ruby.h")
have_func("rb_sym2str", "ruby.h")
have_func("rb_opts_exception_p", "ruby.h")
have_func("rb_category_warn", "ruby.h")
have_const("RB_WARN_CATEGORY_DEPRECATED", "ruby.h")

if File.file?(File.expand_path('../lib/bigdecimal.rb', __FILE__))
  bigdecimal_rb = "$(srcdir)/lib/bigdecimal.rb"
else
  bigdecimal_rb = "$(srcdir)/../../lib/bigdecimal.rb"
end

create_makefile('bigdecimal') {|mf|
  mf << "GEMSPEC = #{gemspec_name}\n"
  mf << "BIGDECIMAL_RB = #{bigdecimal_rb}\n"
}
