require "mkmf"

# may need to be changed
begin
  $LDFLAGS, *libs = `gtk-config --libs`.chomp!.split(/(-l.*)/)
  $libs = libs.join(' ') + ' ' + $libs
  $CFLAGS=`gtk-config --cflags`.chomp!
rescue
  $LDFLAGS = '-L/usr/X11R6/lib -L/usr/local/lib'
  $CFLAGS = '-I/usr/X11R6/lib -I/usr/local/include'
  $libs = '-lm -lc'
end

have_library("X11", "XOpenDisplay")
have_library("Xext", "XShmQueryVersion")
have_library("Xi", "XOpenDevice")
if have_library("glib", "g_print") and
    have_library("gdk", "gdk_init") and
    have_library("gtk", "gtk_init")
  $libs = $libs.split(/\s/).uniq.join(' ')
  create_makefile("gtk")
end
