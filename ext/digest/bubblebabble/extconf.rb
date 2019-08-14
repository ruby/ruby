# frozen_string_literal: false
require 'mkmf'

$defs << "-DHAVE_CONFIG_H"

create_makefile('digest/bubblebabble')
