# frozen_string_literal: false
$INCFLAGS << " -I$(topdir) -I$(top_srcdir)"

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

$srcs = Dir[File.join($srcdir, "*.{#{SRC_EXT.join(%q{,})}}")]
inits = $srcs.map {|s| File.basename(s, ".*")}
inits.delete("init")
inits.map! {|s|"X(#{s})"}
$defs << "-DTEST_INIT_FUNCS(X)=\"#{inits.join(' ')}\""
create_makefile("-test-/file")
