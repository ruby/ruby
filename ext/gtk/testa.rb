require 'gtk'

window = Gtk::Window::new(Gtk::WINDOW_TOPLEVEL)
window.set_title("toolbar test")
window.set_policy(TRUE, TRUE, TRUE)
window.signal_connect("destroy") do
  exit
end
window.signal_connect("delete_event") do
  exit
end
window.border_width(0)
window.realize

toolbar = Gtk::Toolbar::new(Gtk::ORIENTATION_HORIZONTAL, Gtk::TOOLBAR_BOTH)
toolbar.append_item "Horizontal", "Horizontal toolbar layout",
  Gtk::Pixmap::new(*Gdk::Pixmap::create_from_xpm(window.window,
						 nil,
						 #window.style.bg[Gtk::STATE_NORMAL],
						 "test.xpm")), nil do
  toolbar.set_orientation Gtk::ORIENTATION_HORIZONTAL
end
toolbar.append_item "Vertival", "Vertical toolbar layout",
  Gtk::Pixmap::new(*Gdk::Pixmap::create_from_xpm(window.window,
						 nil, #window.style.bg[Gtk::STATE_NORMAL],
						 "test.xpm")), nil do
  toolbar.set_orientation Gtk::ORIENTATION_VERTICAL
end
toolbar.append_space
toolbar.append_item "Icons", "Only show toolbar icons",
  Gtk::Pixmap::new(*Gdk::Pixmap::create_from_xpm(window.window,
						 nil, #window.style.bg[Gtk::STATE_NORMAL],
						 "test.xpm")), nil do
  toolbar.set_style Gtk::TOOLBAR_ICONS
end
toolbar.append_item "Text", "Only show toolbar text",
  Gtk::Pixmap::new(*Gdk::Pixmap::create_from_xpm(window.window,
						 nil,#window.style.bg[Gtk::STATE_NORMAL],
						 "test.xpm")), nil do
  toolbar.set_style Gtk::TOOLBAR_TEXT
end
toolbar.append_item "Both", "Show toolbar icons and text",
  Gtk::Pixmap::new(*Gdk::Pixmap::create_from_xpm(window.window,
						 nil, #window.style.bg[Gtk::STATE_NORMAL],
						 "test.xpm")), nil do
  toolbar.set_style Gtk::TOOLBAR_BOTH
end
toolbar.append_space
toolbar.append_item "Small", "User small spaces",
  Gtk::Pixmap::new(*Gdk::Pixmap::create_from_xpm(window.window,
						 nil,#window.style.bg[Gtk::STATE_NORMAL],
						 "test.xpm")), nil do
  toolbar.set_space_size 5
end
toolbar.append_item "Big", "User big spaces",
  Gtk::Pixmap::new(*Gdk::Pixmap::create_from_xpm(window.window,
						 nil,#window.style.bg[Gtk::STATE_NORMAL],
						 "test.xpm")), nil do
  toolbar.set_space_size 10
end
toolbar.append_space
toolbar.append_item "Enable", "Enable tooltips",
  Gtk::Pixmap::new(*Gdk::Pixmap::create_from_xpm(window.window,
						 nil,#window.style.bg[Gtk::STATE_NORMAL],
						 "test.xpm")), nil do
  toolbar.set_tooltips TRUE
end
toolbar.append_item "Disable", "Disable tooltips",
  Gtk::Pixmap::new(*Gdk::Pixmap::create_from_xpm(window.window,
						 nil,#window.style.bg[Gtk::STATE_NORMAL],
						 "test.xpm")), nil do
  toolbar.set_tooltips FALSE
end
window.add toolbar
toolbar.show
window.show

Gtk::main()
