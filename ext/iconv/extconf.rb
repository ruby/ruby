require 'mkmf'

dir_config("iconv")

if have_header("iconv.h")
  have_library("iconv", "iconv")
  create_makefile("iconv")
end
