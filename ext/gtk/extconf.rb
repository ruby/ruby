require "mkmf"

# may need to be changed
$LDFLAGS="-L/usr/X11R6/lib -L/usr/local/lib"
$CFLAGS=`gtk-config --cflags`

have_library("X11", "XOpenDisplay")
have_library("Xext", "XShmQueryVersion")
have_library("Xi", "XOpenDevice")
if have_library("glib", "g_print") and
    have_library("gdk", "gdk_init") and
    have_library("gtk", "gtk_init")
  create_makefile("gtk")
end
