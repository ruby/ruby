# frozen_string_literal: false
require 'mkmf'
$INCFLAGS << " -I$(top_srcdir)"
create_makefile 'strscan'
