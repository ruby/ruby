require 'mkmf'
have_library("sun", "getpwnam")	# NIS (== YP) interface for IRIX 4
a = have_func("getlogin")
b = have_func("getpwent")
c = have_func("getgrent")
if  a or b or c
  create_makefile("etc")
end
