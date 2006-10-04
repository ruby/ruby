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
  def configure(style=nil, keys=nil)
    if style.kind_of?(Hash)
      keys = style
      style = nil
    end
    style = '.' unless style

    if Tk::Tile::TILE_SPEC_VERSION_ID < 7
      sub_cmd = 'default'
    else
      sub_cmd = 'configure'
    end

    if keys && keys != None
      tk_call('style', sub_cmd, style, *hash_kv(keys))
    else
      tk_call('style', sub_cmd, style)
    end
  end
  alias default configure

  def map(style=nil, keys=nil)
    if style.kind_of?(Hash)
      keys = style
      style = nil
    end
    style = '.' unless style

    if keys && keys != None
      tk_call('style', 'map', style, *hash_kv(keys))
    else
      tk_call('style', 'map', style)
    end
  end

  def lookup(style, opt, state=None, fallback_value=None)
    tk_call('style', 'lookup', style, '-' << opt.to_s, state, fallback_value)
  end

  include Tk::Tile::ParseStyleLayout

  def layout(style=nil, spec=nil)
    if style.kind_of?(Hash)
      spec = style
      style = nil
    end
    style = '.' unless style

    if spec
      tk_call('style', 'layout', style, spec)
    else
      _style_layout(list(tk_call('style', 'layout', style)))
    end
  end

  def element_create(name, type, *args)
    tk_call('style', 'element', 'create', name, type, *args)
  end

  def element_names()
    list(tk_call('style', 'element', 'names'))
  end

  def element_options(elem)
    simplelist(tk_call('style', 'element', 'options', elem))
  end

  def theme_create(name, keys=nil)
    if keys && keys != None
      tk_call('style', 'theme', 'create', name, *hash_kv(keys))
    else
      tk_call('style', 'theme', 'create', name)
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
