#
#  tkextlib/tcllib/style.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
#   * Part of tcllib extension
#   * select and use some 'style' of option (resource) DB
#

require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script
require File.join(File.dirname(File.expand_path(__FILE__)), 'setup.rb')

# TkPackage.require('style', '0.1')
TkPackage.require('style')

module Tk
  module Style
    def self.names
      tk_split_simplelist(tk_call('style::names'))
    end

    def self.use(style)
      tk_call('style::use', style)
    end
  end
end
