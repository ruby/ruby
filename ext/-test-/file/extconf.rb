# frozen_string_literal: false
require_relative "../auto_ext.rb"

headers = %w[sys/param.h sys/mount.h sys/vfs.h].select {|h| have_header(h)}
if have_type("struct statfs", headers)
  have_struct_member("struct statfs", "f_fstypename", headers)
  have_struct_member("struct statfs", "f_type", headers)
  have_struct_member("struct statfs", "f_flags", headers)
end

headers = %w[sys/statvfs.h].select {|h| have_header(h)}
if have_type("struct statvfs", headers)
  have_struct_member("struct statvfs", "f_fstypename", headers)
  have_struct_member("struct statvfs", "f_basetype", headers)
  have_struct_member("struct statvfs", "f_type", headers)
end

auto_ext(inc: true)
