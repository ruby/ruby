require 'gtk'

window = Gtk::Window::new(Gtk::WINDOW_TOPLEVEL)
window.set_title("entry")
window.border_width(0)

box1 = Gtk::VBox::new(FALSE, 0)
window.add(box1)
box1.show

box2 = Gtk::VBox::new(FALSE, 10)
box2.border_width(10)
box1.pack_start(box2, TRUE, TRUE, 0)
box2.show

entry = Gtk::Entry::new()
entry.set_text("hello world")
box2.pack_start(entry, TRUE, TRUE, 0)
entry.show

separator = Gtk::HSeparator::new()
box1.pack_start(separator, FALSE, TRUE, 0)
separator.show

box2 = Gtk::VBox::new(FALSE, 10)
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
