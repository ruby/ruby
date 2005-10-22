#
#  tkextlib/tcllib/widget.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
#   * Part of tcllib extension
#   * megawidget package that uses snit as the object system (snidgets)
#

require 'tk'
require 'tkextlib/tcllib.rb'

# TkPackage.require('widget', '3.0')
TkPackage.require('widget')

module Tk::Tcllib
  module Widget
    PACKAGE_NAME = 'widget'.freeze
    def self.package_name
      PACKAGE_NAME
    end

    def self.package_version
      begin
        TkPackage.require('widget')
      rescue
        ''
      end
    end
  end
end

module Tk::Tcllib::Widget
  autoload :Dialog,             'tkextlib/tcllib/dialog'

  autoload :Panelframe,         'tkextlib/tcllib/panelframe'
  autoload :PanelFrame,         'tkextlib/tcllib/panelframe'

  autoload :Ruler,              'tkextlib/tcllib/ruler'

  autoload :Screenruler,        'tkextlib/tcllib/screenruler'
  autoload :ScreenRuler,        'tkextlib/tcllib/screenruler'

  autoload :Scrolledwindow,     'tkextlib/tcllib/scrollwin'
  autoload :ScrolledWindow,     'tkextlib/tcllib/scrollwin'

  autoload :Superframe,         'tkextlib/tcllib/superframe'
  autoload :SuperFrame,         'tkextlib/tcllib/superframe'
end
