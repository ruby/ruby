require 'gtk'

window = Gtk::Window::new(Gtk::WINDOW_TOPLEVEL)
window.border_width(10)
button = Gtk::Button::new("Hello World")
button.signal_connect("clicked") do
  print "hello world\n"
  exit
end
window.add(button)
button.show
window.show
Gtk::main()
