require 'gtk'

def create_bbox_window(horizontal, title, pos, spacing, cw, ch, layout)
  window = Gtk::Window::new(Gtk::WINDOW_TOPLEVEL)
  window.set_title(title)
  window.signal_connect("delete_event") do
    window.hide
    window.destroy
  end
  if horizontal
    window.set_usize(550, 60)
    window.set_uposition(150, pos)
  else
    window.set_usize(150, 400)
    window.set_uposition(pos, 200)
  end
  box1 = Gtk::VBox::new(FALSE, 0)
  window.add box1
  box1.show
  if horizontal
    bbox = Gtk::HButtonBox::new()
  else
    bbox = Gtk::VButtonBox::new()
  end
  bbox.set_layout layout
  bbox.set_spacing spacing
  bbox.set_child_size cw, ch
  bbox.show
  box1.border_width 25
  box1.pack_start(bbox, TRUE, TRUE, 0)
  button = Gtk::Button::new("OK")
  bbox.add button
  button.signal_connect("clicked") do
    window.hide
    window.destroy
  end
  button.show

  button = Gtk::Button::new("Cancel")
  bbox.add button
  button.signal_connect("clicked") do
    window.hide
    window.destroy
  end
  button.show

  button = Gtk::Button::new("Help")
  bbox.add button
  button.show

  window.show
end

def test_hbbox
  create_bbox_window(TRUE, "Spread", 50, 40, 85, 25, Gtk::BUTTONBOX_SPREAD);
  create_bbox_window(TRUE, "Edge", 250, 40, 85, 28, Gtk::BUTTONBOX_EDGE);
  create_bbox_window(TRUE, "Start", 450, 40, 85, 25, Gtk::BUTTONBOX_START);
  create_bbox_window(TRUE, "End", 650, 15, 30, 25, Gtk::BUTTONBOX_END);
end

def test_vbbox
  create_bbox_window(FALSE, "Spread", 50, 40, 85, 25, Gtk::BUTTONBOX_SPREAD);
  create_bbox_window(FALSE, "Edge", 250, 40, 85, 28, Gtk::BUTTONBOX_EDGE);
  create_bbox_window(FALSE, "Start", 450, 40, 85, 25, Gtk::BUTTONBOX_START);
  create_bbox_window(FALSE, "End", 650, 15, 30, 25, Gtk::BUTTONBOX_END);
end

window = Gtk::Window::new(Gtk::WINDOW_TOPLEVEL)
window.signal_connect("delete_event") do
  window.destroy
  exit
end
window.set_title("button box")
window.border_width(20)

bbox = Gtk::HButtonBox::new()
window.add(bbox)
bbox.show

button = Gtk::Button::new("Horizontal")
def button.clicked(*args)
  test_hbbox
end
bbox.add button
button.show

button = Gtk::Button::new("Vertical")
def button.clicked(*args)
  test_vbbox
end
bbox.add button
button.show
window.show

Gtk::main()
