#
#  style commands
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    module Style
    end
  end
end

module Tk::Tile::Style
  extend TkCore
end

class << Tk::Tile::Style
  def default(style, keys=nil)
    if keys && keys != None
      tk_call('style', 'default', style, *hash_kv(keys))
    else
      tk_call('style', 'default', style)
    end
  end

  def map(style, keys=nil)
    if keys && keys != None
      tk_call('style', 'map', style, *hash_kv(keys))
    else
      tk_call('style', 'map', style)
    end
  end

  def layout(style, spec=nil)
    if spec
      tk_call('style', 'layout', style, spec)
    else
      tk_call('style', 'layout', style)
    end
  end

  def element_create(name, type, *args)
    tk_call('style', 'element', 'create', name, type, *args)
  end

  def element_names()
    list(tk_call('style', 'element', 'names'))
  end

  def theme_create(name, keys=nil)
    if keys && keys != None
      tk_call('style', 'theme', 'create', name, type, *hash_kv(keys))
    else
      tk_call('style', 'theme', 'create', name, type)
    end
  end

  def theme_settings(name, cmd=nil, &b)
    cmd = Proc.new(&b) if !cmd && b
    tk_call('style', 'theme', 'settings', name, cmd)
  end

  def theme_names()
    list(tk_call('style', 'theme', 'names'))
  end

  def theme_use(name)
    tk_call('style', 'theme', 'use', name)
  end
end
