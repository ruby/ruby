# frozen_string_literal: true
require 'mkmf'
if RUBY_ENGINE == 'ruby'
  $INCFLAGS << " -I$(top_srcdir)" if $extmk
  have_func("onig_region_memsize(NULL)")
  have_func("rb_reg_onig_match", "ruby/re.h")
  have_func("rb_deprecate_constant")
  create_makefile 'strscan'
else
  File.write('Makefile', dummy_makefile("").join)
end
