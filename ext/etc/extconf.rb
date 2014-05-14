require 'mkmf'

have_library("sun", "getpwnam")	# NIS (== YP) interface for IRIX 4
have_func("getlogin")
have_func("getpwent")
have_func("getgrent")
sysconfdir = RbConfig.expand(RbConfig::CONFIG["sysconfdir"].dup, "prefix"=>"", "DESTDIR"=>"")
$defs.push("-DSYSCONFDIR=#{Shellwords.escape(sysconfdir.dump)}")

have_struct_member('struct passwd', 'pw_gecos', 'pwd.h')
have_struct_member('struct passwd', 'pw_change', 'pwd.h')
have_struct_member('struct passwd', 'pw_quota', 'pwd.h')
if have_struct_member('struct passwd', 'pw_age', 'pwd.h')
  case what_type?('struct passwd', 'pw_age', 'pwd.h')
  when "string"
    f = "safe_setup_str"
  when "long long"
    f = "LL2NUM"
  else
    f = "INT2NUM"
  end
  $defs.push("-DPW_AGE2VAL="+f)
end
have_struct_member('struct passwd', 'pw_class', 'pwd.h')
have_struct_member('struct passwd', 'pw_comment', 'pwd.h') unless /cygwin/ === RUBY_PLATFORM
have_struct_member('struct passwd', 'pw_expire', 'pwd.h')
have_struct_member('struct passwd', 'pw_passwd', 'pwd.h')
have_struct_member('struct group', 'gr_passwd', 'grp.h')

create_makefile("etc")
