have_library("socket", "socket")
have_library("inet", "gethostbyname")
have_library("nsl", "gethostbyname")
have_header("sys/un.h")
if have_func("socket")
  have_func("hsterror")
  unless have_func("gethostname")
    have_func("uname")
  end
  create_makefile("socket")
end
