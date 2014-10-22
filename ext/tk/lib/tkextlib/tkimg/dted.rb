#
#  TkImg - format 'DTED'
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script
require 'tkextlib/tkimg/setup.rb'

# TkPackage.require('img::dted', '1.4')
TkPackage.require('img::dted')

module Tk
  module Img
    module DTED
      PACKAGE_NAME = 'img::dted'.freeze
      def self.package_name
        PACKAGE_NAME
      end

      def self.package_version
        begin
          TkPackage.require('img::dted')
        rescue
          ''
        end
      end
    end
  end
end
