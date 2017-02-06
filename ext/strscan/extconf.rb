# frozen_string_literal: true
require 'mkmf'
$INCFLAGS << " -I$(top_srcdir)"
create_makefile 'strscan'
