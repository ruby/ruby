#
#  tkextlib/blt/container.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/blt.rb'

module Tk::BLT
  class Container < TkWindow
    TkCommandNames = ['::blt::container'.freeze].freeze
    WidgetClassName = 'Container'.freeze
    WidgetClassNames[WidgetClassName] = self
  end

  def find_command(pat)
    list(tk_send_without_enc(tk_call(self.path, 'find', '-command', pat)))
  end

  def find_name(pat)
    list(tk_send_without_enc(tk_call(self.path, 'find', '-name', pat)))
  end
end
