require 'mkmf'

def etc_grep_header(field)
  f = open("conftest.c", "w")
  f.print <<EOF
#include <pwd.h>
EOF
  f.close
  begin
    if xsystem("#{CPP} | egrep #{field}")
      $defs.push(format("-D%s", field.upcase))
    end
  ensure
    system "rm -f conftest.c"
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
  etc_grep_header("pw_comment")
  etc_grep_header("pw_expire")
  create_makefile("etc")
end
