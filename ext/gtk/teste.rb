require 'gtk'

Gtk::RC::parse_string <<EOS
style "default"
{
  fontset = "-adobe-helvetica-medium-r-normal--*-120-*-*-*-*-*-*,*"
}
widget_class "*" style "default"
EOS

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
entry.select_region(0, -1)
box2.pack_start(entry, TRUE, TRUE, 0)
entry.show

cb = Gtk::Combo::new()
cb.set_popdown_strings(["item0",
			 "item1 item1",
			 "item2 item2 item2",
			 "item3 item3 item3 item3",
			 "item4 item4 item4 item4 item4",
			 "item5 item5 item5 item5 item5 item5",
			 "item6 item6 item6 item6 item6",
			 "item7 item7 item7 item7",
			 "item8 item8 item8",
			 "item9 item9"])
cb.entry.set_text("hello world")
cb.entry.select_region(0, -1)
box2.pack_start(cb, TRUE, TRUE, 0)
cb.show

check = Gtk::CheckButton::new("Editable")
box2.pack_start(check, FALSE, TRUE, 0)
check.signal_connect("toggled") do
  entry.set_editable(check.active)
end
check.set_state(false)
check.show

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
