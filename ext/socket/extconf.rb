$LDFLAGS = "-L/usr/local/lib"
have_library("wsock32", "cygwin32_socket") or have_library("socket", "socket")
have_library("inet", "gethostbyname")
have_library("nsl", "gethostbyname")
have_header("sys/un.h")
if have_func("socket") or have_func("cygwin32_socket")
  have_func("hsterror")
  unless have_func("gethostname")
    have_func("uname")
  end
  if ENV["SOCKS_SERVER"]  # test if SOCKSsocket needed
    if have_library("socks", "Rconnect")
      $CFLAGS="-DSOCKS"
    end
  end
  create_makefile("socket")
end
