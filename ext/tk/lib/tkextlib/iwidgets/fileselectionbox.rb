#
#  tkextlib/iwidgets/fileselectionbox.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/iwidgets.rb'

module Tk
  module Iwidgets
    class Fileselectionbox < Tk::Itk::Widget
    end
  end
end

class Tk::Iwidgets::Fileselectionbox
  TkCommandNames = ['::iwidgets::fileselectionbox'.freeze].freeze
  WidgetClassName = 'Fileselectionbox'.freeze
  WidgetClassNames[WidgetClassName] = self

  def child_site
    window(tk_call(@path, 'childsite'))
  end

  def filter
    tk_call(@path, 'filter')
    self
  end

  def get
    tk_call(@path, 'get')
  end
end
