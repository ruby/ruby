# frozen_string_literal: false
#
#  TkImg - format 'Raw Data'
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script
require 'tkextlib/tkimg/setup.rb'

# TkPackage.require('img::raw', '1.4')
TkPackage.require('img::raw')

module Tk
  module Img
    module Raw
      PACKAGE_NAME = 'img::raw'.freeze
      def self.package_name
        PACKAGE_NAME
      end

      def self.package_version
        begin
          TkPackage.require('img::raw')
        rescue
          ''
        end
      end
    end
  end
end
