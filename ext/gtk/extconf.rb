require "mkmf"
if have_library("glib", "g_print") and
    have_library("gdk", "gdk_init") and
    have_library("gtk", "gtk_init")
  create_makefile("gtk")
end
