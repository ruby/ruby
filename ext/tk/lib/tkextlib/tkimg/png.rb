#
#  TkImg - format 'png'
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script
require 'tkextlib/tkimg/setup.rb'

# TkPackage.require('img::png', '1.3')
TkPackage.require('img::png')

module Tk
  module Img
    module PNG
      def self.package_version
        begin
          TkPackage.require('img::png')
        rescue
          ''
        end
      end
    end
  end
end
