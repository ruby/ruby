# To use the GUI JSON editor, start the edit_json.rb executable script. It
# requires ruby-gtk to be installed.

require 'gtk2'
require 'iconv'
require 'json'
require 'rbconfig'
require 'open-uri'

module JSON
  module Editor
    include Gtk

    # Beginning of the editor window title
    TITLE                 = 'JSON Editor'.freeze

    # Columns constants
    ICON_COL, TYPE_COL, CONTENT_COL = 0, 1, 2

    # JSON primitive types (Containers)
    CONTAINER_TYPES = %w[Array Hash].sort
    # All JSON primitive types
    ALL_TYPES = (%w[TrueClass FalseClass Numeric String NilClass] +
                 CONTAINER_TYPES).sort

    # The Nodes necessary for the tree representation of a JSON document
    ALL_NODES = (ALL_TYPES + %w[Key]).sort

    DEFAULT_DIALOG_KEY_PRESS_HANDLER = lambda do |dialog, event|
      case event.keyval
      when Gdk::Keyval::GDK_Return
        dialog.response Dialog::RESPONSE_ACCEPT
      when Gdk::Keyval::GDK_Escape
        dialog.response Dialog::RESPONSE_REJECT
      end
    end

    # Returns the Gdk::Pixbuf of the icon named _name_ from the icon cache.
    def Editor.fetch_icon(name)
      @icon_cache ||= {}
      unless @icon_cache.key?(name)
        path = File.dirname(__FILE__)
        @icon_cache[name] = Gdk::Pixbuf.new(File.join(path, name + '.xpm'))
      end
     @icon_cache[name]
    end

    # Opens an error dialog on top of _window_ showing the error message
    # _text_.
    def Editor.error_dialog(window, text)
      dialog = MessageDialog.new(window, Dialog::MODAL, 
        MessageDialog::ERROR, 
        MessageDialog::BUTTONS_CLOSE, text)
      dialog.show_all
      dialog.run
    rescue TypeError
      dialog = MessageDialog.new(Editor.window, Dialog::MODAL, 
        MessageDialog::ERROR, 
        MessageDialog::BUTTONS_CLOSE, text)
      dialog.show_all
      dialog.run
    ensure
      dialog.destroy if dialog
    end

    # Opens a yes/no question dialog on top of _window_ showing the error
    # message _text_. If yes was answered _true_ is returned, otherwise
    # _false_.
    def Editor.question_dialog(window, text)
      dialog = MessageDialog.new(window, Dialog::MODAL, 
        MessageDialog::QUESTION, 
        MessageDialog::BUTTONS_YES_NO, text)
      dialog.show_all
      dialog.run do |response|
        return Gtk::Dialog::RESPONSE_YES === response
      end
    ensure
      dialog.destroy if dialog
    end

    # Convert the tree model starting from Gtk::TreeIter _iter_ into a Ruby
    # data structure and return it.
    def Editor.model2data(iter)
      return nil if iter.nil?
      case iter.type
      when 'Hash'
        hash = {}
        iter.each { |c| hash[c.content] = Editor.model2data(c.first_child) }
        hash
      when 'Array'
        array = Array.new(iter.n_children)
        iter.each_with_index { |c, i| array[i] = Editor.model2data(c) }
        array
      when 'Key'
        iter.content
      when 'String'
        iter.content
      when 'Numeric'
        content = iter.content
        if /\./.match(content)
          content.to_f
        else
          content.to_i
        end
      when 'TrueClass'
        true
      when 'FalseClass'
        false
      when 'NilClass'
        nil
      else
        fail "Unknown type found in model: #{iter.type}"
      end
    end

    # Convert the Ruby data structure _data_ into tree model data for Gtk and
    # returns the whole model. If the parameter _model_ wasn't given a new
    # Gtk::TreeStore is created as the model. The _parent_ parameter specifies
    # the parent node (iter, Gtk:TreeIter instance) to which the data is
    # appended, alternativeley the result of the yielded block is used as iter.
    def Editor.data2model(data, model = nil, parent = nil)
      model ||= TreeStore.new(Gdk::Pixbuf, String, String)
      iter = if block_given?
        yield model
      else
        model.append(parent)
      end
      case data
      when Hash
        iter.type = 'Hash'
        data.sort.each do |key, value|
          pair_iter = model.append(iter)
          pair_iter.type    = 'Key'
          pair_iter.content = key.to_s
          Editor.data2model(value, model, pair_iter)
        end
      when Array
        iter.type = 'Array'
        data.each do |value|
          Editor.data2model(value, model, iter)
        end
      when Numeric
        iter.type = 'Numeric'
        iter.content = data.to_s
      when String, true, false, nil
        iter.type    = data.class.name
        iter.content = data.nil? ? 'null' : data.to_s
      else
        iter.type    = 'String'
        iter.content = data.to_s
      end
      model
    end

    # The Gtk::TreeIter class is reopened and some auxiliary methods are added.
    class Gtk::TreeIter
      include Enumerable

      # Traverse each of this Gtk::TreeIter instance's children
      # and yield to them.
      def each
        n_children.times { |i| yield nth_child(i) }
      end

      # Recursively traverse all nodes of this Gtk::TreeIter's subtree
      # (including self) and yield to them.
      def recursive_each(&block)
        yield self
        each do |i|
          i.recursive_each(&block)
        end
      end

      # Remove the subtree of this Gtk::TreeIter instance from the
      # model _model_.
      def remove_subtree(model)
        while current = first_child
          model.remove(current)
        end
      end

      # Returns the type of this node.
      def type
        self[TYPE_COL]
      end

      # Sets the type of this node to _value_. This implies setting
      # the respective icon accordingly.
      def type=(value)
        self[TYPE_COL] = value
        self[ICON_COL] = Editor.fetch_icon(value)
      end

      # Returns the content of this node.
      def content
        self[CONTENT_COL]
      end

      # Sets the content of this node to _value_.
      def content=(value)
        self[CONTENT_COL] = value
      end
    end

    # This module bundles some method, that can be used to create a menu. It
    # should be included into the class in question.
    module MenuExtension
      include Gtk

      # Creates a Menu, that includes MenuExtension. _treeview_ is the
      # Gtk::TreeView, on which it operates.
      def initialize(treeview)
        @treeview = treeview
        @menu = Menu.new
      end

      # Returns the Gtk::TreeView of this menu.
      attr_reader :treeview

      # Returns the menu.
      attr_reader :menu

      # Adds a Gtk::SeparatorMenuItem to this instance's #menu.
      def add_separator
        menu.append SeparatorMenuItem.new
      end

      # Adds a Gtk::MenuItem to this instance's #menu. _label_ is the label
      # string, _klass_ is the item type, and _callback_ is the procedure, that
      # is called if the _item_ is activated.
      def add_item(label, keyval = nil, klass = MenuItem, &callback)
        label = "#{label} (C-#{keyval.chr})" if keyval
        item = klass.new(label)
        item.signal_connect(:activate, &callback)
        if keyval
          self.signal_connect(:'key-press-event') do |item, event|
            if event.state & Gdk::Window::ModifierType::CONTROL_MASK != 0 and
              event.keyval == keyval
              callback.call item
            end
          end
        end
        menu.append item
        item
      end

      # This method should be implemented in subclasses to create the #menu of
      # this instance. It has to be called after an instance of this class is
      # created, to build the menu.
      def create
        raise NotImplementedError
      end

      def method_missing(*a, &b)
        treeview.__send__(*a, &b)
      end
    end

    # This class creates the popup menu, that opens when clicking onto the
    # treeview.
    class PopUpMenu
      include MenuExtension

      # Change the type or content of the selected node.
      def change_node(item)
        if current = selection.selected
          parent = current.parent
          old_type, old_content = current.type, current.content
          if ALL_TYPES.include?(old_type)
            @clipboard_data = Editor.model2data(current)
            type, content = ask_for_element(parent, current.type,
              current.content)
            if type
              current.type, current.content = type, content
              current.remove_subtree(model)
              toplevel.display_status("Changed a node in tree.")
              window.change
            end
          else
            toplevel.display_status(
              "Cannot change node of type #{old_type} in tree!")
          end
        end
      end

      # Cut the selected node and its subtree, and save it into the
      # clipboard.
      def cut_node(item)
        if current = selection.selected
          if current and current.type == 'Key'
            @clipboard_data = {
              current.content => Editor.model2data(current.first_child)
            }
          else
            @clipboard_data = Editor.model2data(current)
          end
          model.remove(current)
          window.change
          toplevel.display_status("Cut a node from tree.")
        end
      end

      # Copy the selected node and its subtree, and save it into the
      # clipboard.
      def copy_node(item)
        if current = selection.selected
          if current and current.type == 'Key'
            @clipboard_data = {
              current.content => Editor.model2data(current.first_child)
            }
          else
            @clipboard_data = Editor.model2data(current)
          end
          window.change
          toplevel.display_status("Copied a node from tree.")
        end
      end

      # Paste the data in the clipboard into the selected Array or Hash by
      # appending it.
      def paste_node_appending(item)
        if current = selection.selected
          if @clipboard_data
            case current.type
            when 'Array'
              Editor.data2model(@clipboard_data, model, current)
              expand_collapse(current)
            when 'Hash'
              if @clipboard_data.is_a? Hash
                parent = current.parent
                hash = Editor.model2data(current)
                model.remove(current)
                hash.update(@clipboard_data)
                Editor.data2model(hash, model, parent)
                if parent
                  expand_collapse(parent)
                elsif @expanded
                  expand_all
                end
                window.change
              else
                toplevel.display_status(
                  "Cannot paste non-#{current.type} data into '#{current.type}'!")
              end
            else
              toplevel.display_status(
                "Cannot paste node below '#{current.type}'!")
            end
          else
            toplevel.display_status("Nothing to paste in clipboard!")
          end
        else
            toplevel.display_status("Append a node into the root first!")
        end
      end

      # Paste the data in the clipboard into the selected Array inserting it
      # before the selected element.
      def paste_node_inserting_before(item)
        if current = selection.selected
          if @clipboard_data
            parent = current.parent or return
            parent_type = parent.type
            if parent_type == 'Array'
              selected_index = parent.each_with_index do |c, i|
                break i if c == current
              end
              Editor.data2model(@clipboard_data, model, parent) do |m|
                m.insert_before(parent, current)
              end
              expand_collapse(current)
              toplevel.display_status("Inserted an element to " +
                "'#{parent_type}' before index #{selected_index}.")
              window.change
            else
              toplevel.display_status(
                "Cannot insert node below '#{parent_type}'!")
            end
          else
            toplevel.display_status("Nothing to paste in clipboard!")
          end
        else
            toplevel.display_status("Append a node into the root first!")
        end
      end

      # Append a new node to the selected Hash or Array.
      def append_new_node(item)
        if parent = selection.selected
          parent_type = parent.type
          case parent_type
          when 'Hash'
            key, type, content = ask_for_hash_pair(parent)
            key or return
            iter = create_node(parent, 'Key', key)
            iter = create_node(iter, type, content)
            toplevel.display_status(
              "Added a (key, value)-pair to '#{parent_type}'.")
            window.change
          when 'Array'
            type, content = ask_for_element(parent)
            type or return
            iter = create_node(parent, type, content)
            window.change
            toplevel.display_status("Appendend an element to '#{parent_type}'.")
          else
            toplevel.display_status("Cannot append to '#{parent_type}'!")
          end
        else
          type, content = ask_for_element
          type or return
          iter = create_node(nil, type, content)
          window.change
        end
      end

      # Insert a new node into an Array before the selected element.
      def insert_new_node(item)
        if current = selection.selected
          parent = current.parent or return
          parent_parent = parent.parent
          parent_type = parent.type
          if parent_type == 'Array'
            selected_index = parent.each_with_index do |c, i|
              break i if c == current
            end
            type, content = ask_for_element(parent)
            type or return
            iter = model.insert_before(parent, current)
            iter.type, iter.content = type, content
            toplevel.display_status("Inserted an element to " +
              "'#{parent_type}' before index #{selected_index}.")
            window.change
          else
            toplevel.display_status(
              "Cannot insert node below '#{parent_type}'!")
          end
        else
            toplevel.display_status("Append a node into the root first!")
        end
      end

      # Recursively collapse/expand a subtree starting from the selected node.
      def collapse_expand(item)
        if current = selection.selected
          if row_expanded?(current.path)
            collapse_row(current.path)
          else
            expand_row(current.path, true)
          end
        else
            toplevel.display_status("Append a node into the root first!")
        end
      end

      # Create the menu.
      def create
        add_item("Change node", ?n, &method(:change_node))
        add_separator
        add_item("Cut node", ?X, &method(:cut_node))
        add_item("Copy node", ?C, &method(:copy_node))
        add_item("Paste node (appending)", ?A, &method(:paste_node_appending))
        add_item("Paste node (inserting before)", ?I,
          &method(:paste_node_inserting_before))
        add_separator
        add_item("Append new node", ?a, &method(:append_new_node))
        add_item("Insert new node before", ?i, &method(:insert_new_node))
        add_separator 
        add_item("Collapse/Expand node (recursively)", ?e,
          &method(:collapse_expand))

        menu.show_all
        signal_connect(:button_press_event) do |widget, event|
          if event.kind_of? Gdk::EventButton and event.button == 3
            menu.popup(nil, nil, event.button, event.time)
          end
        end
        signal_connect(:popup_menu) do
          menu.popup(nil, nil, 0, Gdk::Event::CURRENT_TIME)
        end
      end
    end

    # This class creates the File pulldown menu.
    class FileMenu
      include MenuExtension

      # Clear the model and filename, but ask to save the JSON document, if
      # unsaved changes have occured.
      def new(item)
        window.clear
      end

      # Open a file and load it into the editor. Ask to save the JSON document
      # first, if unsaved changes have occured.
      def open(item)
        window.file_open
      end

      def open_location(item)
        window.location_open
      end

      # Revert the current JSON document in the editor to the saved version.
      def revert(item)
        window.instance_eval do
          @filename and file_open(@filename) 
        end
      end

      # Save the current JSON document.
      def save(item)
        window.file_save
      end

      # Save the current JSON document under the given filename.
      def save_as(item)
        window.file_save_as
      end

      # Quit the editor, after asking to save any unsaved changes first.
      def quit(item)
        window.quit
      end

      # Create the menu.
      def create
        title = MenuItem.new('File')
        title.submenu = menu
        add_item('New', &method(:new))
        add_item('Open', ?o, &method(:open))
        add_item('Open location', ?l, &method(:open_location))
        add_item('Revert', &method(:revert))
        add_separator
        add_item('Save', ?s, &method(:save))
        add_item('Save As', ?S, &method(:save_as))
        add_separator
        add_item('Quit', ?q, &method(:quit))
        title
      end
    end

    # This class creates the Edit pulldown menu.
    class EditMenu
      include MenuExtension

      # Copy data from model into primary clipboard.
      def copy(item)
        data = Editor.model2data(model.iter_first)
        json = JSON.pretty_generate(data, :max_nesting => false)
        c = Gtk::Clipboard.get(Gdk::Selection::PRIMARY)
        c.text = json
      end

      # Copy json text from primary clipboard into model.
      def paste(item)
        c = Gtk::Clipboard.get(Gdk::Selection::PRIMARY)
        if json = c.wait_for_text
          window.ask_save if @changed
          begin
            window.edit json
          rescue JSON::ParserError
            window.clear
          end
        end
      end

      # Find a string in all nodes' contents and select the found node in the
      # treeview.
      def find(item)
        @search = ask_for_find_term(@search) or return
        iter = model.get_iter('0') or return
        iter.recursive_each do |i|
          if @iter
            if @iter != i
              next
            else
              @iter = nil
              next
            end
          elsif @search.match(i[CONTENT_COL])
             set_cursor(i.path, nil, false)
             @iter = i
             break
          end
        end
      end

      # Repeat the last search given by #find.
      def find_again(item)
        @search or return
        iter = model.get_iter('0')
        iter.recursive_each do |i|
          if @iter
            if @iter != i
              next
            else
              @iter = nil
              next
            end
          elsif @search.match(i[CONTENT_COL])
             set_cursor(i.path, nil, false)
             @iter = i
             break
          end
        end
      end

      # Sort (Reverse sort) all elements of the selected array by the given
      # expression. _x_ is the element in question.
      def sort(item)
        if current = selection.selected
          if current.type == 'Array'
            parent = current.parent
            ary = Editor.model2data(current)
            order, reverse = ask_for_order
            order or return
            begin
              block = eval "lambda { |x| #{order} }"
              if reverse
                ary.sort! { |a,b| block[b] <=> block[a] }
              else
                ary.sort! { |a,b| block[a] <=> block[b] }
              end
            rescue => e
              Editor.error_dialog(self, "Failed to sort Array with #{order}: #{e}!")
            else
              Editor.data2model(ary, model, parent) do |m|
                m.insert_before(parent, current)
              end
              model.remove(current)
              expand_collapse(parent)
              window.change
              toplevel.display_status("Array has been sorted.")
            end
          else
            toplevel.display_status("Only Array nodes can be sorted!")
          end
        else
            toplevel.display_status("Select an Array to sort first!")
        end
      end

      # Create the menu.
      def create
        title = MenuItem.new('Edit')
        title.submenu = menu
        add_item('Copy', ?c, &method(:copy))
        add_item('Paste', ?v, &method(:paste))
        add_separator
        add_item('Find', ?f, &method(:find))
        add_item('Find Again', ?g, &method(:find_again))
        add_separator
        add_item('Sort', ?S, &method(:sort))
        title
      end
    end

    class OptionsMenu
      include MenuExtension

      # Collapse/Expand all nodes by default.
      def collapsed_nodes(item)
        if expanded
          self.expanded = false
          collapse_all
        else
          self.expanded = true
          expand_all 
        end
      end

      # Toggle pretty saving mode on/off.
      def pretty_saving(item)
        @pretty_item.toggled
        window.change
      end

      attr_reader :pretty_item

      # Create the menu.
      def create
        title = MenuItem.new('Options')
        title.submenu = menu
        add_item('Collapsed nodes', nil, CheckMenuItem, &method(:collapsed_nodes))
        @pretty_item = add_item('Pretty saving', nil, CheckMenuItem,
          &method(:pretty_saving))
        @pretty_item.active = true
        window.unchange
        title
      end
    end

    # This class inherits from Gtk::TreeView, to configure it and to add a lot
    # of behaviour to it.
    class JSONTreeView < Gtk::TreeView
      include Gtk

      # Creates a JSONTreeView instance, the parameter _window_ is
      # a MainWindow instance and used for self delegation.
      def initialize(window)
        @window = window
        super(TreeStore.new(Gdk::Pixbuf, String, String))
        self.selection.mode = SELECTION_BROWSE

        @expanded = false
        self.headers_visible = false
        add_columns
        add_popup_menu
      end

      # Returns the MainWindow instance of this JSONTreeView.
      attr_reader :window

      # Returns true, if nodes are autoexpanding, false otherwise.
      attr_accessor :expanded

      private

      def add_columns
        cell = CellRendererPixbuf.new
        column = TreeViewColumn.new('Icon', cell,
          'pixbuf'      => ICON_COL
        )
        append_column(column)

        cell = CellRendererText.new
        column = TreeViewColumn.new('Type', cell,
          'text'      => TYPE_COL
        )
        append_column(column)

        cell = CellRendererText.new
        cell.editable = true
        column = TreeViewColumn.new('Content', cell,
          'text'       => CONTENT_COL
        )
        cell.signal_connect(:edited, &method(:cell_edited))
        append_column(column)
      end

      def unify_key(iter, key)
        return unless iter.type == 'Key'
        parent = iter.parent
        if parent.any? { |c| c != iter and c.content == key }
          old_key = key
          i = 0
          begin
            key = sprintf("%s.%d", old_key, i += 1)
          end while parent.any? { |c| c != iter and c.content == key }
        end
        iter.content = key
      end

      def cell_edited(cell, path, value)
        iter = model.get_iter(path)
        case iter.type
        when 'Key'
          unify_key(iter, value)
          toplevel.display_status('Key has been changed.')
        when 'FalseClass'
          value.downcase!
          if value == 'true'
            iter.type, iter.content = 'TrueClass', 'true'
          end
        when 'TrueClass'
          value.downcase!
          if value == 'false'
            iter.type, iter.content = 'FalseClass', 'false'
          end
        when 'Numeric'
          iter.content = (Integer(value) rescue Float(value) rescue 0).to_s
        when 'String'
          iter.content = value
        when 'Hash', 'Array'
          return
        else
          fail "Unknown type found in model: #{iter.type}"
        end
        window.change
      end

      def configure_value(value, type)
        value.editable = false
        case type
        when 'Array', 'Hash'
          value.text = ''
        when 'TrueClass'
          value.text = 'true'
        when 'FalseClass'
          value.text = 'false'
        when 'NilClass'
          value.text = 'null'
        when 'Numeric', 'String'
          value.text ||= ''
          value.editable = true
        else
          raise ArgumentError, "unknown type '#{type}' encountered"
        end
      end

      def add_popup_menu
        menu = PopUpMenu.new(self)
        menu.create
      end

      public

      # Create a _type_ node with content _content_, and add it to _parent_
      # in the model. If _parent_ is nil, create a new model and put it into
      # the editor treeview.
      def create_node(parent, type, content)
        iter = if parent
          model.append(parent)
        else
          new_model = Editor.data2model(nil)
          toplevel.view_new_model(new_model)
          new_model.iter_first
        end
        iter.type, iter.content = type, content
        expand_collapse(parent) if parent
        iter
      end

      # Ask for a hash key, value pair to be added to the Hash node _parent_.
      def ask_for_hash_pair(parent)
        key_input = type_input = value_input = nil

        dialog = Dialog.new("New (key, value) pair for Hash", nil, nil,
          [ Stock::OK, Dialog::RESPONSE_ACCEPT ],
          [ Stock::CANCEL, Dialog::RESPONSE_REJECT ]
        )
        dialog.width_request = 640

        hbox = HBox.new(false, 5)
        hbox.pack_start(Label.new("Key:"), false)
        hbox.pack_start(key_input = Entry.new)
        key_input.text = @key || ''
        dialog.vbox.pack_start(hbox, false)
        key_input.signal_connect(:activate) do
          if parent.any? { |c| c.content == key_input.text }
            toplevel.display_status('Key already exists in Hash!')
            key_input.text = ''
          else
            toplevel.display_status('Key has been changed.')
          end
        end

        hbox = HBox.new(false, 5)
        hbox.pack_start(Label.new("Type:"), false)
        hbox.pack_start(type_input = ComboBox.new(true))
        ALL_TYPES.each { |t| type_input.append_text(t) }
        type_input.active = @type || 0
        dialog.vbox.pack_start(hbox, false)

        type_input.signal_connect(:changed) do
          value_input.editable = false
          case ALL_TYPES[type_input.active]
          when 'Array', 'Hash'
            value_input.text = ''
          when 'TrueClass'
            value_input.text = 'true'
          when 'FalseClass'
            value_input.text = 'false'
          when 'NilClass'
            value_input.text = 'null'
          else
            value_input.text = ''
            value_input.editable = true
          end
        end

        hbox = HBox.new(false, 5)
        hbox.pack_start(Label.new("Value:"), false)
        hbox.pack_start(value_input = Entry.new)
        value_input.width_chars = 60
        value_input.text = @value || ''
        dialog.vbox.pack_start(hbox, false)

        dialog.signal_connect(:'key-press-event', &DEFAULT_DIALOG_KEY_PRESS_HANDLER)
        dialog.show_all
        self.focus = dialog
        dialog.run do |response| 
          if response == Dialog::RESPONSE_ACCEPT
            @key = key_input.text
            type = ALL_TYPES[@type = type_input.active]
            content = value_input.text
            return @key, type, content
          end
        end
        return
      ensure
        dialog.destroy
      end

      # Ask for an element to be appended _parent_.
      def ask_for_element(parent = nil, default_type = nil, value_text = @content)
        type_input = value_input = nil

        dialog = Dialog.new(
          "New element into #{parent ? parent.type : 'root'}",
          nil, nil,
          [ Stock::OK, Dialog::RESPONSE_ACCEPT ],
          [ Stock::CANCEL, Dialog::RESPONSE_REJECT ]
        )
        hbox = HBox.new(false, 5)
        hbox.pack_start(Label.new("Type:"), false)
        hbox.pack_start(type_input = ComboBox.new(true))
        default_active = 0
        types = parent ? ALL_TYPES : CONTAINER_TYPES
        types.each_with_index do |t, i|
          type_input.append_text(t)
          if t == default_type
            default_active = i
          end
        end
        type_input.active = default_active
        dialog.vbox.pack_start(hbox, false)
        type_input.signal_connect(:changed) do
          configure_value(value_input, types[type_input.active])
        end

        hbox = HBox.new(false, 5)
        hbox.pack_start(Label.new("Value:"), false)
        hbox.pack_start(value_input = Entry.new)
        value_input.width_chars = 60
        value_input.text = value_text if value_text
        configure_value(value_input, types[type_input.active])

        dialog.vbox.pack_start(hbox, false)

        dialog.signal_connect(:'key-press-event', &DEFAULT_DIALOG_KEY_PRESS_HANDLER)
        dialog.show_all
        self.focus = dialog
        dialog.run do |response| 
          if response == Dialog::RESPONSE_ACCEPT
            type = types[type_input.active]
            @content = case type
            when 'Numeric'
              Integer(value_input.text) rescue Float(value_input.text) rescue 0
            else
              value_input.text
            end.to_s
            return type, @content
          end
        end
        return
      ensure
        dialog.destroy if dialog
      end

      # Ask for an order criteria for sorting, using _x_ for the element in
      # question. Returns the order criterium, and true/false for reverse
      # sorting.
      def ask_for_order
        dialog = Dialog.new(
          "Give an order criterium for 'x'.",
          nil, nil,
          [ Stock::OK, Dialog::RESPONSE_ACCEPT ],
          [ Stock::CANCEL, Dialog::RESPONSE_REJECT ]
        )
        hbox = HBox.new(false, 5)

        hbox.pack_start(Label.new("Order:"), false)
        hbox.pack_start(order_input = Entry.new)
        order_input.text = @order || 'x'
        order_input.width_chars = 60

        hbox.pack_start(reverse_checkbox = CheckButton.new('Reverse'), false)

        dialog.vbox.pack_start(hbox, false)

        dialog.signal_connect(:'key-press-event', &DEFAULT_DIALOG_KEY_PRESS_HANDLER)
        dialog.show_all
        self.focus = dialog
        dialog.run do |response| 
          if response == Dialog::RESPONSE_ACCEPT
            return @order = order_input.text, reverse_checkbox.active?
          end
        end
        return
      ensure
        dialog.destroy if dialog
      end

      # Ask for a find term to search for in the tree. Returns the term as a
      # string.
      def ask_for_find_term(search = nil)
        dialog = Dialog.new(
          "Find a node matching regex in tree.",
          nil, nil,
          [ Stock::OK, Dialog::RESPONSE_ACCEPT ],
          [ Stock::CANCEL, Dialog::RESPONSE_REJECT ]
        )
        hbox = HBox.new(false, 5)

        hbox.pack_start(Label.new("Regex:"), false)
        hbox.pack_start(regex_input = Entry.new)
        hbox.pack_start(icase_checkbox = CheckButton.new('Icase'), false)
        regex_input.width_chars = 60
        if search
          regex_input.text = search.source
          icase_checkbox.active = search.casefold?
        end

        dialog.vbox.pack_start(hbox, false)

        dialog.signal_connect(:'key-press-event', &DEFAULT_DIALOG_KEY_PRESS_HANDLER)
        dialog.show_all
        self.focus = dialog
        dialog.run do |response| 
          if response == Dialog::RESPONSE_ACCEPT
            begin
              return Regexp.new(regex_input.text, icase_checkbox.active? ? Regexp::IGNORECASE : 0)
            rescue => e
              Editor.error_dialog(self, "Evaluation of regex /#{regex_input.text}/ failed: #{e}!")
              return
            end
          end
        end
        return
      ensure
        dialog.destroy if dialog
      end

      # Expand or collapse row pointed to by _iter_ according
      # to the #expanded attribute.
      def expand_collapse(iter)
        if expanded
          expand_row(iter.path, true)
        else
          collapse_row(iter.path)
        end
      end
    end

    # The editor main window
    class MainWindow < Gtk::Window
      include Gtk

      def initialize(encoding)
        @changed  = false
        @encoding = encoding
        super(TOPLEVEL)
        display_title
        set_default_size(800, 600)
        signal_connect(:delete_event) { quit }

        vbox = VBox.new(false, 0)
        add(vbox)
        #vbox.border_width = 0

        @treeview = JSONTreeView.new(self)
        @treeview.signal_connect(:'cursor-changed') do
          display_status('')
        end

        menu_bar = create_menu_bar
        vbox.pack_start(menu_bar, false, false, 0)

        sw = ScrolledWindow.new(nil, nil)
        sw.shadow_type = SHADOW_ETCHED_IN
        sw.set_policy(POLICY_AUTOMATIC, POLICY_AUTOMATIC)
        vbox.pack_start(sw, true, true, 0)
        sw.add(@treeview)

        @status_bar = Statusbar.new
        vbox.pack_start(@status_bar, false, false, 0)

        @filename ||= nil
        if @filename
          data = read_data(@filename)
          view_new_model Editor.data2model(data)
        end

        signal_connect(:button_release_event) do |_,event|
          if event.button == 2
            c = Gtk::Clipboard.get(Gdk::Selection::PRIMARY)
            if url = c.wait_for_text
              location_open url
            end
            false
          else
            true
          end
        end
      end

      # Creates the menu bar with the pulldown menus and returns it.
      def create_menu_bar
        menu_bar = MenuBar.new
        @file_menu = FileMenu.new(@treeview)
        menu_bar.append @file_menu.create
        @edit_menu = EditMenu.new(@treeview)
        menu_bar.append @edit_menu.create
        @options_menu = OptionsMenu.new(@treeview)
        menu_bar.append @options_menu.create
        menu_bar
      end

      # Sets editor status to changed, to indicate that the edited data
      # containts unsaved changes.
      def change
        @changed = true
        display_title
      end

      # Sets editor status to unchanged, to indicate that the edited data
      # doesn't containt unsaved changes.
      def unchange
        @changed = false
        display_title
      end

      # Puts a new model _model_ into the Gtk::TreeView to be edited.
      def view_new_model(model)
        @treeview.model     = model
        @treeview.expanded  = true
        @treeview.expand_all
        unchange
      end

      # Displays _text_ in the status bar.
      def display_status(text)
        @cid ||= nil
        @status_bar.pop(@cid) if @cid
        @cid = @status_bar.get_context_id('dummy')
        @status_bar.push(@cid, text)
      end

      # Opens a dialog, asking, if changes should be saved to a file.
      def ask_save
        if Editor.question_dialog(self,
          "Unsaved changes to JSON model. Save?")
          if @filename
            file_save
          else
            file_save_as
          end
        end
      end

      # Quit this editor, that is, leave this editor's main loop.
      def quit
        ask_save if @changed
        if Gtk.main_level > 0
          destroy
          Gtk.main_quit
        end
        nil
      end

      # Display the new title according to the editor's current state.
      def display_title
        title = TITLE.dup
        title << ": #@filename" if @filename
        title << " *" if @changed
        self.title = title
      end

      # Clear the current model, after asking to save all unsaved changes.
      def clear
        ask_save if @changed
        @filename = nil
        self.view_new_model nil
      end

      def check_pretty_printed(json)
        pretty = !!((nl_index = json.index("\n")) && nl_index != json.size - 1)
        @options_menu.pretty_item.active = pretty
      end
      private :check_pretty_printed

      # Open the data at the location _uri_, if given. Otherwise open a dialog
      # to ask for the _uri_.
      def location_open(uri = nil)
        uri = ask_for_location unless uri
        uri or return
        ask_save if @changed
        data = load_location(uri) or return
        view_new_model Editor.data2model(data)
      end

      # Open the file _filename_ or call the #select_file method to ask for a
      # filename.
      def file_open(filename = nil)
        filename = select_file('Open as a JSON file') unless filename
        data = load_file(filename) or return
        view_new_model Editor.data2model(data)
      end

      # Edit the string _json_ in the editor.
      def edit(json)
        if json.respond_to? :read
          json = json.read
        end
        data = parse_json json
        view_new_model Editor.data2model(data)
      end

      # Save the current file.
      def file_save
        if @filename
          store_file(@filename)
        else
          file_save_as
        end
      end

      # Save the current file as the filename 
      def file_save_as
        filename = select_file('Save as a JSON file')
        store_file(filename)
      end

      # Store the current JSON document to _path_.
      def store_file(path)
        if path
          data = Editor.model2data(@treeview.model.iter_first)
          File.open(path + '.tmp', 'wb') do |output|
            data or break
            if @options_menu.pretty_item.active?
              output.puts JSON.pretty_generate(data, :max_nesting => false)
            else
              output.write JSON.generate(data, :max_nesting => false)
            end
          end
          File.rename path + '.tmp', path
          @filename = path
          toplevel.display_status("Saved data to '#@filename'.")
          unchange
        end
      rescue SystemCallError => e
        Editor.error_dialog(self, "Failed to store JSON file: #{e}!")
      end
  
      # Load the file named _filename_ into the editor as a JSON document.
      def load_file(filename)
        if filename
          if File.directory?(filename)
            Editor.error_dialog(self, "Try to select a JSON file!")
            nil
          else
            @filename = filename
            if data = read_data(filename)
              toplevel.display_status("Loaded data from '#@filename'.")
            end
            display_title
            data
          end
        end
      end

      # Load the data at location _uri_ into the editor as a JSON document.
      def load_location(uri)
        data = read_data(uri) or return
        @filename = nil
        toplevel.display_status("Loaded data from '#{uri}'.")
        display_title
        data
      end

      def parse_json(json)
        check_pretty_printed(json)
        if @encoding && !/^utf8$/i.match(@encoding)
          iconverter = Iconv.new('utf8', @encoding)
          json = iconverter.iconv(json)
        end
        JSON::parse(json, :max_nesting => false, :create_additions => false)
      end
      private :parse_json

      # Read a JSON document from the file named _filename_, parse it into a
      # ruby data structure, and return the data.
      def read_data(filename)
        open(filename) do |f|
          json = f.read
          return parse_json(json)
        end
      rescue => e
        Editor.error_dialog(self, "Failed to parse JSON file: #{e}!")
        return
      end

      # Open a file selecton dialog, displaying _message_, and return the
      # selected filename or nil, if no file was selected.
      def select_file(message)
        filename = nil
        fs = FileSelection.new(message)
        fs.set_modal(true)
        @default_dir = File.join(Dir.pwd, '') unless @default_dir
        fs.set_filename(@default_dir)
        fs.set_transient_for(self)
        fs.signal_connect(:destroy) { Gtk.main_quit }
        fs.ok_button.signal_connect(:clicked) do
          filename = fs.filename
          @default_dir = File.join(File.dirname(filename), '')
          fs.destroy
          Gtk.main_quit
        end
        fs.cancel_button.signal_connect(:clicked) do
          fs.destroy
          Gtk.main_quit
        end
        fs.show_all
        Gtk.main
        filename
      end

      # Ask for location URI a to load data from. Returns the URI as a string.
      def ask_for_location
        dialog = Dialog.new(
          "Load data from location...",
          nil, nil,
          [ Stock::OK, Dialog::RESPONSE_ACCEPT ],
          [ Stock::CANCEL, Dialog::RESPONSE_REJECT ]
        )
        hbox = HBox.new(false, 5)

        hbox.pack_start(Label.new("Location:"), false)
        hbox.pack_start(location_input = Entry.new)
        location_input.width_chars = 60
        location_input.text = @location || ''

        dialog.vbox.pack_start(hbox, false)

        dialog.signal_connect(:'key-press-event', &DEFAULT_DIALOG_KEY_PRESS_HANDLER)
        dialog.show_all
        dialog.run do |response| 
          if response == Dialog::RESPONSE_ACCEPT
            return @location = location_input.text
          end
        end
        return
      ensure
        dialog.destroy if dialog
      end
    end

    class << self
      # Starts a JSON Editor. If a block was given, it yields
      # to the JSON::Editor::MainWindow instance.
      def start(encoding = 'utf8') # :yield: window
        Gtk.init
        @window = Editor::MainWindow.new(encoding)
        @window.icon_list = [ Editor.fetch_icon('json') ]
        yield @window if block_given?
        @window.show_all
        Gtk.main
      end

      # Edit the string _json_ with encoding _encoding_ in the editor.
      def edit(json, encoding = 'utf8')
        start(encoding) do |window|
          window.edit json
        end
      end

      attr_reader :window
    end
  end
end
