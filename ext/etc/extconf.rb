require 'mkmf'

def etc_grep_header(field)
  if egrep_cpp(field, "#include <pwd.h>\n")
    $defs.push(format("-D%s", field.upcase))
  end
end

have_library("sun", "getpwnam")	# NIS (== YP) interface for IRIX 4
a = have_func("getlogin")
b = have_func("getpwent")
c = have_func("getgrent")
if  a or b or c
  etc_grep_header("pw_gecos")
  etc_grep_header("pw_change")
  etc_grep_header("pw_quota")
  etc_grep_header("pw_age")
  etc_grep_header("pw_class")
  etc_grep_header("pw_comment") unless /cygwin/ === RUBY_PLATFORM
  etc_grep_header("pw_expire")
  create_makefile("etc")
end
