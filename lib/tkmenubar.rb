#
# tkmenubar.rb
#
# Copyright (C) 1998 maeda shugo. All rights reserved. 
# This file can be distributed under the terms of the Ruby.

# Usage:
#
# menu_spec = [
#   [['File', 0],
#     ['Open', proc{puts('Open clicked')}, 0],
#     '---',
#     ['Quit', proc{exit}, 0]],
#   [['Edit', 0],
#     ['Cut', proc{puts('Cut clicked')}, 2],
#     ['Copy', proc{puts('Copy clicked')}, 0],
#     ['Paste', proc{puts('Paste clicked')}, 0]]
# ]
# menubar = TkMenubar.new(nil, menu_spec,
# 			'tearoff'=>false,
# 			'foreground'=>'grey40',
# 			'activeforeground'=>'red',
# 			'font'=>'-adobe-helvetica-bold-r-*--12-*-iso8859-1')
# menubar.pack('side'=>'top', 'fill'=>'x')
#
#
# OR
#
#
# menubar = TkMenubar.new
# menubar.add_menu([['File', 0],
# 		   ['Open', proc{puts('Open clicked')}, 0],
# 		   '---',
# 		   ['Quit', proc{exit}, 0]])
# menubar.add_menu([['Edit', 0],
# 		   ['Cut', proc{puts('Cut clicked')}, 2],
# 		   ['Copy', proc{puts('Copy clicked')}, 0],
# 		   ['Paste', proc{puts('Paste clicked')}, 0]])
# menubar.configure('tearoff', false)
# menubar.configure('foreground', 'grey40')
# menubar.configure('activeforeground', 'red')
# menubar.configure('font', '-adobe-helvetica-bold-r-*--12-*-iso8859-1')
# menubar.pack('side'=>'top', 'fill'=>'x')

# The format of the menu_spec is:
# [
#   [
#     [button text, underline, accelerator],
#     [menu label, command, underline, accelerator],
#     '---', # separator
#     ...
#   ],
#   ...
# ]

# underline and accelerator are optional parameters.
# Hashes are OK instead of Arrays.

# To use add_menu, configuration must be done by calling configure after
# adding all menus by add_menu, not by the constructor arguments.

require "tk"

class TkMenubar<TkFrame
  
  include TkComposite
  
  def initialize(parent = nil, spec = nil, options = nil)
    super(parent, options)
    
    @menus = []
    
    if spec
      for menu_info in spec
	add_menu(menu_info)
      end
    end
    
    if options
      for key, value in options
	configure(key, value)
      end
    end
  end

  def add_menu(menu_info)
    btn_info = menu_info.shift
    mbtn = TkMenubutton.new(@frame)
    
    if btn_info.kind_of?(Hash)
      for key, value in btn_info
	mbtn.configure(key, value)
      end
    elsif btn_info.kind_of?(Array)
      mbtn.configure('text', btn_info[0]) if btn_info[0]
      mbtn.configure('underline', btn_info[1]) if btn_info[1]
      mbtn.configure('accelerator', btn_info[2]) if btn_info[2]
    else
      mbtn.configure('text', btn_info)
    end
    
    menu = TkMenu.new(mbtn)
    
    for item_info in menu_info
      if item_info.kind_of?(Hash)
	menu.add('command', item_info)
      elsif item_info.kind_of?(Array)
	options = {}
	options['label'] = item_info[0] if item_info[0]
	options['command'] = item_info[1] if item_info[1]
	options['underline'] = item_info[2] if item_info[2]
	options['accelerator'] = item_info[3] if item_info[3]
	menu.add('command', options)
      elsif /^-+$/ =~ item_info
	menu.add('sep')
      else
	menu.add('command', 'label' => item_info)
      end
    end
    
    mbtn.menu(menu)
    @menus.push([mbtn, menu])
    delegate('tearoff', menu)
    delegate('foreground', mbtn, menu)
    delegate('background', mbtn, menu)
    delegate('disabledforeground', mbtn, menu)
    delegate('activeforeground', mbtn, menu)
    delegate('activebackground', mbtn, menu)
    delegate('font', mbtn, menu)
    delegate('kanjifont', mbtn, menu)
    mbtn.pack('side' => 'left')
  end
  
  def [](index)
    return @menus[index]
  end
end
