require 'gtk'

window = Gtk::Window::new(Gtk::WINDOW_TOPLEVEL)
window.set_title("buttons")
window.border_width(0)

box1 = Gtk::VBox::new(FALSE, 0)
window.add(box1)
box1.show

table = Gtk::Table::new(3, 3, FALSE)
table.set_row_spacings(5)
table.set_col_spacings(5)
table.border_width(10)
box1.pack_start(table, TRUE, TRUE, 0)
table.show

button = []
0.upto(8) do |i|
  button.push Gtk::Button::new("button"+(i+1))
end
0.upto(8) do |i|
  button[i].signal_connect("clicked") do |w|
    j = (i+1)%9
    if button[j].visible?
      button[j].hide
    else
      button[j].show
    end
  end
  button[i].show
end
table.attach(button[0], 0, 1, 0, 1, nil, nil, 0, 0)
table.attach(button[1], 1, 2, 1, 2, nil, nil, 0, 0)
table.attach(button[2], 2, 3, 2, 3, nil, nil, 0, 0)
table.attach(button[3], 0, 1, 2, 3, nil, nil, 0, 0)
table.attach(button[4], 2, 3, 0, 1, nil, nil, 0, 0)
table.attach(button[5], 1, 2, 2, 3, nil, nil, 0, 0)
table.attach(button[6], 1, 2, 0, 1, nil, nil, 0, 0)
table.attach(button[7], 2, 3, 1, 2, nil, nil, 0, 0)
table.attach(button[8], 0, 1, 1, 2, nil, nil, 0, 0)

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
