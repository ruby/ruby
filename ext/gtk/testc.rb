require 'gtk'

window = Gtk::Window::new(Gtk::WINDOW_TOPLEVEL)
window.signal_connect("destroy") do
  exit
end
window.signal_connect("delete_event") do
  exit
end
window.set_title("pixmap")
window.border_width(0)
window.realize

box1 = Gtk::VBox::new(FALSE, 0)
window.add box1
box1.show

box2 = Gtk::HBox::new(FALSE, 10)
box2.border_width 10
box1.pack_start box2, TRUE, TRUE, 0
box2.show

button = Gtk::Button::new()
box2.pack_start button, FALSE, FALSE, 0
button.show

style = button.style
pixmap, mask = Gdk::Pixmap::create_from_xpm(window.window,
					    nil,
					    #style.bg[Gtk::STATE_NORMAL],
					    "test.xpm")
pixmapwid = Gtk::Pixmap::new(pixmap, mask)
label = Gtk::Label::new("Pixmap\ntest")
box3 = Gtk::HBox::new(FALSE, 0)
box3.border_width 2
box3.add pixmapwid
box3.add label
button.add box3
pixmapwid.show
label.show
box3.show

separator = Gtk::HSeparator::new()
box1.pack_start(separator, FALSE, TRUE, 0)
separator.show

box2 = Gtk::HBox::new(FALSE, 10)
box2.border_width(10)
box1.pack_start(box2, FALSE, TRUE, 0)
box2.show

button = Gtk::Button::new("close")
button.signal_connect("clicked") do
  window.destroy
  exit
end
box2.pack_start(button, TRUE, TRUE, 0)
button.set_flags(Gtk::CAN_DEFAULT);
button.grab_default
button.show

window.show

Gtk::main()
