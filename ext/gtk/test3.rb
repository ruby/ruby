require 'gtk'

window = Gtk::FileSelection::new("file selection dialog")
window.position(Gtk::WIN_POS_MOUSE)
window.border_width(0)

window.ok_button.signal_connect("clicked") do
  print window.get_filename, "\n"
end
window.cancel_button.signal_connect("clicked") do
  window.destroy
  exit
end
window.show

Gtk::main()
