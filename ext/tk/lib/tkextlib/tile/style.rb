#
#  style commands
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script  --  <libdir>/tkextlib/tile.rb
require(File.dirname(File.expand_path(__FILE__)) + '.rb')

module Tk::Tile::Style
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
  end

  def theme_names()
    list(tk_call('style', 'theme', 'names'))
  end

  def theme_use(name)
    tk_call('style', 'use', name)
  end
end
