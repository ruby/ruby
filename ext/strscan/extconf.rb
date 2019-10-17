# frozen_string_literal: true
require 'mkmf'
$INCFLAGS << " -I$(top_srcdir)" if $extmk
have_func("onig_region_memsize", "ruby.h")
create_makefile 'strscan'
