require "mkmf"

$CPPFLAGS = "-DEXT_MATHN -DCANON -DCLCANON "

create_makefile "mathn/complex"
