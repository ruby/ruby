#
#  tkextlib/iwidgets/mainwindow.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/iwidgets.rb'

module Tk
  module Iwidgets
    class Mainwindow < Tk::Iwidgets::Shell
    end
  end
end

class Tk::Iwidgets::Mainwindow
  TkCommandNames = ['::iwidgets::mainwindow'.freeze].freeze
  WidgetClassName = 'Mainwindow'.freeze
  WidgetClassNames[WidgetClassName] = self

  def child_site
    window(tk_call(@path, 'childsite'))
  end

  def menubar(*args)
    unless args.empty?
      tk_call(@path, 'menubar', *args)
    end
    window(tk_call(@path, 'menubar'))
  end

  def mousebar(*args)
    unless args.empty?
      tk_call(@path, 'mousebar', *args)
    end
    window(tk_call(@path, 'mousebar'))
  end

  def msgd(*args)
    unless args.empty?
      tk_call(@path, 'msgd', *args)
    end
    window(tk_call(@path, 'msgd'))
  end

  def toolbar(*args)
    unless args.empty?
      tk_call(@path, 'toolbar', *args)
    end
    window(tk_call(@path, 'toolbar'))
  end
end
