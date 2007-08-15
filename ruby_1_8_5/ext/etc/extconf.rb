require 'mkmf'

have_library("sun", "getpwnam")	# NIS (== YP) interface for IRIX 4
a = have_func("getlogin")
b = have_func("getpwent")
c = have_func("getgrent")
if  a or b or c
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
  [%w"uid_t pwd.h", %w"gid_t grp.h"].each do |t, *h|
    h.unshift("sys/types.h")
    f = "INT2NUM"
    if have_type(t, h)
      if try_static_assert("sizeof(#{t}) > sizeof(long)", h)
	f = "LL2NUM"
      end
      if try_static_assert("(#{t})-1 > 0", h)
	f = "U#{f}"
      end
    end
    t = t.chomp('_t').upcase
    $defs.push("-DPW_#{t}2VAL=#{f}")
    $defs.push("-DPW_VAL2#{t}=#{f.sub(/([A-Z]+)2(NUM)/, '\22\1')}")
  end
  create_makefile("etc")
end
