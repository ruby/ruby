#
#  TkImg - format 'bmp'
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script
require File.join(File.dirname(File.expand_path(__FILE__)), 'setup.rb')

#TkPackage.require('img::bmp', '1.3')
TkPackage.require('img::bmp')
