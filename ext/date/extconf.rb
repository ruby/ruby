# frozen_string_literal: true
require 'mkmf'
config_string("strict_warnflags") {|w| $warnflags += " #{w}"}
create_makefile('date_core')
