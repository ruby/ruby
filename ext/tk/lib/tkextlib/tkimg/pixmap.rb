#
#  TkImg - format 'pixmap'
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script
require 'tkextlib/tkimg/setup.rb'

# TkPackage.require('img::pixmap', '1.3')
TkPackage.require('img::pixmap')

module Tk
  module Img
    module PIXMAP
      def self.package_version
        begin
          TkPackage.require('img::pixmap')
        rescue
          ''
        end
      end
    end
  end
end

class TkPixmapImage<TkImage
  def self.version
    Tk::Img::PIXMAP.version
  end

  def initialize(*args)
    @type = 'pixmap'
    super
  end
end
