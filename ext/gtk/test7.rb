require 'gtk'

window = Gtk::Window::new(Gtk::WINDOW_TOPLEVEL)
window.set_title("check buttons")
window.border_width(0)

box1 = Gtk::VBox::new(FALSE, 0)
window.add(box1)
box1.show

box2 = Gtk::VBox::new(FALSE, 10)
box2.border_width(10)
box1.pack_start(box2, TRUE, TRUE, 0)
box2.show

button = Gtk::CheckButton::new("button1")
box2.pack_start(button, TRUE, TRUE, 0)
button.show

button = Gtk::CheckButton::new("button2")
box2.pack_start(button, TRUE, TRUE, 0)
button.show

button = Gtk::CheckButton::new("button3")
box2.pack_start(button, TRUE, TRUE, 0)
button.show

separator = Gtk::HSeparator::new()
box1.pack_start(separator, FALSE, TRUE, 0)
separator.show

box2 = Gtk::VBox::new(FALSE, 10)
box2.border_width(10)
box1.pack_start(box2, FALSE, TRUE, 0)
box2.show

close = Gtk::Button::new("close")
close.signal_connect("clicked") do
  window.destroy
  exit
end
box2.pack_start(close, TRUE, TRUE, 0)
close.set_flags(Gtk::CAN_DEFAULT);
close.grab_default
close.show

window.show

Gtk::main()
