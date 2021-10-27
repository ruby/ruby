# frozen_string_literal: true
require 'mkmf'

config_string("strict_warnflags") {|w| $warnflags += " #{w}"}

with_werror("", {:werror => true}) do |opt, |
  have_var("timezone", "time.h", opt)
  have_var("altzone", "time.h", opt)
end

create_makefile('date_core')
