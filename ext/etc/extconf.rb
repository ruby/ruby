# frozen_string_literal: true
require 'mkmf'

headers = []
%w[sys/utsname.h].each {|h|
  if have_header(h, headers)
    headers << h
  end
}
have_library("sun", "getpwnam")	# NIS (== YP) interface for IRIX 4
have_func("uname((struct utsname *)NULL)", headers)
have_func("getlogin")
have_func("getpwent")
have_func("getgrent")
if (sysconfdir = RbConfig::CONFIG["sysconfdir"] and
    !RbConfig.expand(sysconfdir.dup, "prefix"=>"", "DESTDIR"=>"").empty?)
  $defs.push("-DSYSCONFDIR=#{Shellwords.escape(sysconfdir.dump)}")
end

have_func("sysconf")
have_func("confstr")
have_func("fpathconf")

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

# for https://github.com/ruby/etc
srcdir = File.expand_path("..", __FILE__)
if !File.exist?("#{srcdir}/depend")
  %x[#{RbConfig.ruby} #{srcdir}/mkconstants.rb -o #{srcdir}/constdefs.h]
end

have_func('rb_deprecate_constant(Qnil, "None")')

$distcleanfiles << "constdefs.h"

create_makefile("etc")
