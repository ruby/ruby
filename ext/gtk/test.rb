require 'gtk'

def create_menu(depth)
  return nil if depth < 1
  
  menu = Gtk::Menu::new()
  group = nil
  submenu = nil

  for i in 0..4
    buf = sprintf("item %2d - %d", depth, i+1)
#    menuitem = Gtk::MenuItem::new(buf)
    menuitem = Gtk::RadioMenuItem.new(group, buf)
    group = menuitem.group
    if depth % 2
      menuitem.set_show_toggle TRUE
    end
    menu.append menuitem
    menuitem.show
    if depth > 0
      unless submenu
	submenu = create_menu(depth - 1)
      end
      menuitem.set_submenu submenu
    end
  end
  return menu
end

window = Gtk::Window::new(Gtk::WINDOW_TOPLEVEL)
window.signal_connect("destroy") do
  exit
end
window.signal_connect("delete_event") do
  exit
end
window.set_title("menus")
window.border_width(0)

box1 = Gtk::VBox::new(FALSE, 0)
window.add box1
box1.show

menubar = Gtk::MenuBar::new()
box1.pack_start menubar, FALSE, TRUE, 0
menubar.show

menu = create_menu(2)
menuitem = Gtk::MenuItem::new("test\nline2")
menuitem.set_submenu menu
menubar.append menuitem
menuitem.show

menuitem = Gtk::MenuItem::new("foo")
menuitem.set_submenu menu
menubar.append menuitem
menuitem.show

menuitem = Gtk::MenuItem::new("bar")
menuitem.set_submenu menu
menubar.append menuitem
menuitem.show

box2 = Gtk::VBox::new(FALSE, 10)
box2.border_width 10
box1.pack_start box2, TRUE, TRUE, 0
box2.show

optionmenu = Gtk::OptionMenu::new()
optionmenu.set_menu create_menu(1)
optionmenu.set_history 4
box2.pack_start optionmenu, TRUE, TRUE, 0
optionmenu.show

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
