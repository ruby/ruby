#
#  tkextlib/iwidgets/labeledframe.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/iwidgets.rb'

module Tk
  module Iwidgets
    class Labeledframe < Tk::Itk::Archetype
    end
  end
end

class Tk::Iwidgets::Labeledframe
  TkCommandNames = ['::iwidgets::labeledframe'.freeze].freeze
  WidgetClassName = 'Labeledframe'.freeze
  WidgetClassNames[WidgetClassName] = self

  def child_site
    window(tk_call(@path, 'childsite'))
  end
end
