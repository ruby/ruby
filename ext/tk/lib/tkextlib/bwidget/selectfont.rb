#
#  tkextlib/bwidget/selectfont.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/bwidget.rb'
require 'tkextlib/bwidget/messagedlg'

module Tk
  module BWidget
    class SelectFont < Tk::BWidget::MessageDlg
      class Dialog < Tk::BWidget::SelectFont
      end
      class Toolbar < TkWindow
      end
    end
  end
end

class Tk::BWidget::SelectFont
  extend Tk

  TkCommandNames = ['SelectFont'.freeze].freeze
  WidgetClassName = 'SelectFont'.freeze
  WidgetClassNames[WidgetClassName] = self

  def __font_optkeys
    [] # without fontobj operation
  end

  def create
    tk_call(self.class::TkCommandNames[0], @path, *hash_kv(@keys))
  end

  def self.load_font
    tk_call('SelectFont::loadfont')
  end
end

class Tk::BWidget::SelectFont::Dialog
  def __font_optkeys
    [] # without fontobj operation
  end

  def create_self(keys)
    super(keys)
    @keys['type'] = 'dialog'
  end

  def configure(slot, value=None)
    if slot.kind_of?(Hash)
      slot.delete['type']
      slot.delete[:type]
      return self if slot.empty?
    else
      return self if slot == 'type' || slot == :type
    end
    super(slot, value)
  end

  def create
    @keys['type'] = 'dialog'
    tk_call(Tk::BWidget::SelectFont::TkCommandNames[0], @path, *hash_kv(@keys))
  end
end

class Tk::BWidget::SelectFont::Toolbar
  def __font_optkeys
    [] # without fontobj operation
  end

  def create_self(keys)
    keys = {} unless keys
    keys = _symbolkey2str(keys)
    keys['type'] = 'toolbar'
    tk_call(Tk::BWidget::SelectFont::TkCommandNames[0], @path, *hash_kv(keys))
  end
end
