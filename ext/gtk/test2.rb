require 'gtk'

window = Gtk::Window::new(Gtk::WINDOW_TOPLEVEL)
window.set_title("list")
window.border_width(0)

box1 = Gtk::VBox::new(FALSE, 0)
window.add(box1)
box1.show

box2 = Gtk::VBox::new(FALSE, 10)
box2.border_width(10)
box1.pack_start(box2, TRUE, TRUE, 0)
box2.show

scrolled_win = Gtk::ScrolledWindow::new()
scrolled_win.set_policy(Gtk::POLICY_AUTOMATIC,Gtk::POLICY_AUTOMATIC)
box2.pack_start(scrolled_win, TRUE, TRUE, 0)
scrolled_win.show

list = Gtk::List::new()
list.set_selection_mode(Gtk::SELECTION_MULTIPLE)
list.set_selection_mode(Gtk::SELECTION_BROWSE)
scrolled_win.add(list)
list.show

for i in [
    "hello",
    "world",
    "blah",
    "foo",
    "bar",
    "argh",
    "spencer",
    "is a",
    "wussy",
    "programmer",
  ]
  list_item = Gtk::ListItem::new(i)
  list.add(list_item)
  list_item.show
end

button = Gtk::Button::new("add")
button.set_flags(Gtk::CAN_FOCUS);
i = 1
button.signal_connect("clicked") do
  list_item = Gtk::ListItem::new(format("added item %d", i))
  list.add(list_item)
  list_item.show
  i += 1
end
box2.pack_start(button, FALSE, TRUE, 0)
button.show

button = Gtk::Button::new("remove")
button.set_flags(Gtk::CAN_FOCUS);
button.signal_connect("clicked") do
  tmp_list = list.selection
  list.remove_items(tmp_list)
  for w in tmp_list
    w.destroy
  end
end
box2.pack_start(button, FALSE, TRUE, 0)
button.show

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
