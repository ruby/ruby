require 'gtk'

window = Gtk::Window::new(Gtk::WINDOW_TOPLEVEL)
window.signal_connect("destroy") do
  exit
end
window.signal_connect("delete_event") do
  exit
end
window.set_title("buttons")
window.border_width(0)

box1 = Gtk::VBox::new(FALSE, 0)
window.add box1
box1.show

box2 = Gtk::HBox::new(FALSE, 5)
box2.border_width 10
box1.pack_start box2, TRUE, TRUE, 0
box2.show

label = Gtk::Label::new("Hello World")
frame = Gtk::Frame::new("Frame 1")
box2.pack_start frame, TRUE, TRUE, 0
frame.show

box3 = Gtk::VBox::new(FALSE, 5)
box3.border_width 5
frame.add box3
box3.show

button = Gtk::Button::new("switch")
button.signal_connect("clicked") do
  label.reparent box3
end
box3.pack_start button, FALSE, TRUE, 0
button.show
box3.pack_start label, FALSE, TRUE, 0
label.show

frame = Gtk::Frame::new("Frame 2")
box2.pack_start frame, TRUE, TRUE, 0
frame.show

box4 = Gtk::VBox::new(FALSE, 5)
box4.border_width 5
frame.add box4
box4.show

button = Gtk::Button::new("switch")
button.signal_connect("clicked") do
  label.reparent box4
end
box4.pack_start button, FALSE, TRUE, 0
button.show

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
