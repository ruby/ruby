require "mkmf"

# may need to be changed
$LDFLAGS=`gtk-config --libs`.chomp!
$CFLAGS=`gtk-config --cflags`.chomp!

have_library("X11", "XOpenDisplay")
have_library("Xext", "XShmQueryVersion")
have_library("Xi", "XOpenDevice")
if have_library("glib", "g_print") and
    have_library("gdk", "gdk_init") and
    have_library("gtk", "gtk_init")
  create_makefile("gtk")
end
