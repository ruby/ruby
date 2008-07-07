#
# tk/menuspec.rb
#                              Hidethoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
# based on tkmenubar.rb :
#   Copyright (C) 1998 maeda shugo. All rights reserved. 
#   This file can be distributed under the terms of the Ruby.
#
# The format of the menu_spec is:
#   [ menu_info, menu_info, ... ]
#
# And the format of the menu_info is:
#   [
#     [text, underline, configs], # menu button/entry (*1)
#     [label, command, underline, accelerator, configs],   # command entry
#     [label, TkVar_obj, underline, accelerator, configs], # checkbutton entry
#     [label, [TkVar_obj, value], 
#                        underline, accelerator, configs], # radiobutton entry
#     [label, [[...menu_info...], [...menu_info...], ...], 
#                        underline, accelerator, configs], # cascade entry (*2)
#     '---', # separator
#     ...
#   ]
#
# underline, accelerator, and configs are optional pearameters. 
# Hashes are OK instead of Arrays. Then the entry type ('command', 
# 'checkbutton', 'radiobutton' or 'cascade') is given by 'type' key
# (e.g. :type=>'cascade'). When type is 'cascade', an array of menu_info
# is acceptable for 'menu' key (then, create sub-menu).
#
# NOTE: (*1)
#   If you want to make special menus (*.help for UNIX, *.system for Win, 
#   and *.apple for Mac), append 'menu_name'=>name (name is 'help' for UNIX, 
#   'system' for Win, and 'apple' for Mac) option to the configs hash of 
#   menu button/entry information.
#
# NOTE: (*2)
#   If you want to configure a cascade menu, add :menu_config=>{...configs..}
#   to the configs of the cascade entry.

module TkMenuSpec
  def _create_menu(parent, menu_info, menu_name = nil, 
                   tearoff = false, default_opts = nil)
    if tearoff.kind_of?(Hash)
      default_opts = tearoff
      tearoff = false
    end

    if menu_name.kind_of?(Hash)
      default_opts = menu_name
      menu_name = nil
      tearoff = false
    end

    if default_opts.kind_of?(Hash)
      orig_opts = _symbolkey2str(default_opts)
    else
      orig_opts = {}
    end

    tearoff = orig_opts.delete('tearoff') if orig_opts.key?('tearoff')

    if menu_name
      menu = TkMenu.new(parent, :widgetname=>menu_name, :tearoff=>tearoff)
    else
      menu = TkMenu.new(parent, :tearoff=>tearoff)
    end

    for item_info in menu_info
      if item_info.kind_of?(Hash)
        options = orig_opts.dup
        options.update(_symbolkey2str(item_info))
        item_type = (options.delete('type') || 'command').to_s
        menu_name = options.delete('menu_name')
        menu_opts = orig_opts.dup
        menu_opts.update(_symbolkey2str(options.delete('menu_config') || {}))
        if item_type == 'cascade' && options['menu'].kind_of?(Array)
          # create cascade menu
          submenu = _create_menu(menu, options['menu'], menu_name, 
                                 tearoff, menu_opts)
          options['menu'] = submenu
        end
        menu.add(item_type, options)

      elsif item_info.kind_of?(Array)
        options = orig_opts.dup

        options['label'] = item_info[0] if item_info[0]

        case item_info[1]
        when TkVariable
          # checkbutton
          item_type = 'checkbutton'
          options['variable'] = item_info[1]
          options['onvalue']  = true
          options['offvalue'] = false

        when Array
          # radiobutton or cascade
          if item_info[1][0].kind_of?(TkVariable)
            # radiobutton
            item_type = 'radiobutton'
            options['variable'] = item_info[1][0]
            options['value'] = item_info[1][1] if item_info[1][1]

          else
            # cascade
            item_type = 'cascade'
            menu_opts = orig_opts.dup
            if item_info[4] && item_info[4].kind_of?(Hash)
              opts = _symbolkey2str(item_info[4])
              menu_name = opts.delete('menu_name')
              menu_config = opts.delete('menu_config') || {}
              menu_opts.update(_symbolkey2str(menu_config))
            end
            submenu = _create_menu(menu, item_info[1], menu_name, 
                                   tearoff, menu_opts)
            options['menu'] = submenu
          end

        else
          # command
          item_type = 'command'
          options['command'] = item_info[1] if item_info[1]
        end

        options['underline'] = item_info[2] if item_info[2]
        options['accelerator'] = item_info[3] if item_info[3]
        if item_info[4] && item_info[4].kind_of?(Hash)
          opts = _symbolkey2str(item_info[4])
          if item_type == 'cascade'
            opts.delete('menu_name')
            opts.delete('menu_config')
          end
          options.update(opts)
        end
        menu.add(item_type, options)

      elsif /^-+$/ =~ item_info
        menu.add('separator')

      else
        menu.add('command', 'label' => item_info)
      end
    end

    menu
  end
  private :_create_menu

  def _use_menubar?(parent)
    use_menubar = false
    if parent.kind_of?(TkRoot) || parent.kind_of?(TkToplevel)
      return true 
    else
      begin
        parent.cget('menu')
        return true 
      rescue
      end
    end
    false
  end
  private :_use_menubar?

  def _create_menu_for_menubar(parent)
    unless (mbar = parent.menu).kind_of?(TkMenu)
      mbar = TkMenu.new(parent, :tearoff=>false)
      parent.menu(mbar)
    end
    mbar
  end
  private :_create_menu_for_menubar

  def _create_menubutton(parent, menu_info, tearoff=false, default_opts = nil)
    btn_info = menu_info[0]

    if tearoff.kind_of?(Hash)
      default_opts = tearoff
      tearoff = false
    end

    if default_opts.kind_of?(Hash)
      keys = _symbolkey2str(default_opts)
    else
      keys = {}
    end

    tearoff = keys.delete('tearoff') if keys.key?('tearoff')

    if _use_menubar?(parent)
      # menubar by menu entries

      mbar = _create_menu_for_menubar(parent)

      menu_name = nil

      if btn_info.kind_of?(Hash)
        keys.update(_symbolkey2str(btn_info))
        menu_name = keys.delete('menu_name')
        keys['label'] = keys.delete('text') if keys.key?('text')
      elsif btn_info.kind_of?(Array)
        keys['label'] = btn_info[0] if btn_info[0]
        keys['underline'] = btn_info[1] if btn_info[1]
        if btn_info[2]&&btn_info[2].kind_of?(Hash)
          keys.update(_symbolkey2str(btn_info[2]))
          menu_name = keys.delete('menu_name')
        end
      else
        keys = {:label=>btn_info}
      end

      menu = _create_menu(mbar, menu_info[1..-1], menu_name, 
                          tearoff, default_opts)
      menu.tearoff(tearoff)

      keys['menu'] = menu
      mbar.add('cascade', keys)

      [mbar, menu]

    else
      # menubar by menubuttons
      mbtn = TkMenubutton.new(parent)

      menu_name = nil

      if btn_info.kind_of?(Hash)
        keys.update(_symbolkey2str(btn_info))
        menu_name = keys.delete('menu_name')
        keys['text'] = keys.delete('label') if keys.key?('label')
        mbtn.configure(keys)
      elsif btn_info.kind_of?(Array)
        mbtn.configure('text', btn_info[0]) if btn_info[0]
        mbtn.configure('underline', btn_info[1]) if btn_info[1]
        # mbtn.configure('accelerator', btn_info[2]) if btn_info[2]
        if btn_info[2]&&btn_info[2].kind_of?(Hash)
          keys.update(_symbolkey2str(btn_info[2]))
          menu_name = keys.delete('menu_name')
          mbtn.configure(keys)
        end
      else
        mbtn.configure('text', btn_info)
      end

      mbtn.pack('side' => 'left')

      menu = _create_menu(mbtn, menu_info[1..-1], menu_name, 
                          tearoff, default_opts)
    
      mbtn.menu(menu)

      [mbtn, menu]
    end
  end
  private :_create_menubutton

  def _get_cascade_menus(menu)
    menus = []
    (0..(menu.index('last'))).each{|idx|
      if menu.menutype(idx) == 'cascade'
        submenu = menu.entrycget(idx, 'menu')
        menus << [submenu, _get_cascade_menus(submenu)]
      end
    }
    menus
  end
  private :_get_cascade_menus
end
