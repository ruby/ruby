#
#  tkextlib/tcllib/style.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
#   * Part of tcllib extension
#   * select and use some 'style' of option (resource) DB
#

require 'tk'
require 'tkextlib/tcllib.rb'

# TkPackage.require('style', '0.1')
TkPackage.require('style')

module Tk
  module Style
    def self.package_version
      begin
	TkPackage.require('style')
      rescue
	''
      end
    end

    def self.names
      tk_split_simplelist(tk_call('style::names'))
    end

    def self.use(style)
      tk_call('style::use', style)
    end
  end
end
