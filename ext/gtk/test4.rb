require 'gtk'

window = Gtk::Window::new(Gtk::WINDOW_TOPLEVEL)
window.set_title("notebook")
window.border_width(0)

box1 = Gtk::VBox::new(FALSE, 0)
window.add(box1)
box1.show

box2 = Gtk::VBox::new(FALSE, 10)
box2.border_width(10)
box1.pack_start(box2, TRUE, TRUE, 0)
box2.show

notebook = Gtk::Notebook::new()
notebook.set_tab_pos(Gtk::POS_TOP)
box2.pack_start(notebook, TRUE, TRUE, 0)
notebook.show

for i in 1..5
  frame = Gtk::Frame::new(format("Page %d", i))
  frame.border_width(10)
  frame.set_usize(200, 150)
  frame.show

  label = Gtk::Label::new(format("Box %d", i))
  frame.add label
  label.show

  label = Gtk::Label::new(format("Tab %d", i))
  notebook.append_page frame, label
end

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

button = Gtk::Button::new("next")
button.signal_connect("clicked") do
  notebook.next_page
end
box2.pack_start(button, TRUE, TRUE, 0)
button.show

button = Gtk::Button::new("prev")
button.signal_connect("clicked") do
  notebook.prev_page
end
box2.pack_start(button, TRUE, TRUE, 0)
button.show

button = Gtk::Button::new("rotate")
button.signal_connect("clicked") do
  notebook.set_tab_pos((notebook.tab_pos+1)%4)
end
box2.pack_start(button, TRUE, TRUE, 0)
button.show

window.show

Gtk::main()
