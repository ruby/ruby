#
#  tkextlib/iwidgets/labeledwidget.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/iwidgets.rb'

module Tk
  module Iwidgets
    class Labeledwidget < Tk::Itk::Widget
    end
  end
end

class Tk::Iwidgets::Labeledwidget
  extend TkCore

  TkCommandNames = ['::iwidgets::labeledwidget'.freeze].freeze
  WidgetClassName = 'Labeledwidget'.freeze
  WidgetClassNames[WidgetClassName] = self

  def self.alignlabels(*wins)
    tk_call('::iwidgets::Labeledwidget::alignlabels', *wins)
  end

  def child_site
    window(tk_call(@path, 'childsite'))
  end
end
