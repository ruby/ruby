require 'mkmf'

have_library("sun", "getpwnam")	# NIS (== YP) interface for IRIX 4
a = have_func("getlogin")
b = have_func("getpwent")
c = have_func("getgrent")
if  a or b or c
  have_struct_member('struct passwd', 'pw_gecos', 'pwd.h')
  have_struct_member('struct passwd', 'pw_change', 'pwd.h')
  have_struct_member('struct passwd', 'pw_quota', 'pwd.h')
  have_struct_member('struct passwd', 'pw_age', 'pwd.h')
  have_struct_member('struct passwd', 'pw_class', 'pwd.h')
  have_struct_member('struct passwd', 'pw_comment', 'pwd.h') unless /cygwin/ === RUBY_PLATFORM
  have_struct_member('struct passwd', 'pw_expire', 'pwd.h')
  have_struct_member('struct passwd', 'pw_passwd', 'pwd.h')
  have_struct_member('struct group', 'gr_passwd', 'grp.h')
  create_makefile("etc")
end
