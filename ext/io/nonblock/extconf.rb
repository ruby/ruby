# frozen_string_literal: false
require 'mkmf'
target = "io/nonblock"

unless RUBY_ENGINE == 'ruby'
  File.write("Makefile", dummy_makefile($srcdir).join(""))
  return
end

have_func("rb_io_descriptor")

hdr = %w"fcntl.h"
if have_macro("O_NONBLOCK", hdr) and
    (have_macro("F_GETFL", hdr) or have_macro("F_SETFL", hdr))
  create_makefile(target)
end
