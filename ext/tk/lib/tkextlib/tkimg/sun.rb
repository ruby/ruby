#
#  TkImg - format 'sun'
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script
require 'tkextlib/tkimg/setup.rb'

# TkPackage.require('img::sun', '1.3')
TkPackage.require('img::sun')

module Tk
  module Img
    module SUN
      def self.package_version
        begin
          TkPackage.require('img::sun')
        rescue
          ''
        end
      end
    end
  end
end
