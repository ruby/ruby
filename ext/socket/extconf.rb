have_library("inet", "gethostbyname")
have_library("socket", "socket")
have_header("sys/un.h")
if have_func("socket")
  create_makefile("socket")
end
