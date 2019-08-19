# frozen_string_literal: true
require 'mkmf'

config_string("strict_warnflags") {|w| $warnflags += " #{w}"}

have_var("timezone", "time.h")
have_var("altzone", "time.h")

create_makefile('date_core')
