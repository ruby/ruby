#
#  TkImg extension support
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script
require 'tkextlib/tkimg/setup.rb'

# load all image format handlers
#TkPackage.require('Img', '1.3')
TkPackage.require('Img')

module Tk
  module Img
    def self.package_version
      begin
        TkPackage.require('Img')
      rescue
        ''
      end
    end
  end
end

# autoload
autoload :TkPixmapImage, 'tkextlib/tkimg/pixmap'
