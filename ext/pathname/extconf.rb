# frozen_string_literal: false
require 'mkmf'
have_struct_member("struct stat", "st_birthtimespec", "sys/stat.h")
create_makefile('pathname')
