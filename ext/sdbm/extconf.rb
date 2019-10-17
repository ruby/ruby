# frozen_string_literal: false
require 'mkmf'

$defs << "-D""BADMESS=0"
create_makefile("sdbm")
