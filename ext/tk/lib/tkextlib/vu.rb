#
#  The vu widget set support
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# library directory
dir = File.expand_path(__FILE__).sub(/#{File.extname(__FILE__)}$/, '')

# call setup script
require File.join(dir, 'setup.rb')

# load package
# TkPackage.require('vu', '2.1')
#TkPackage.require('vu')

# autoload
module Tk
  module Vu
    # load package
    # VERSION = TkPackage.require('vu', '2.1')
    VERSION = TkPackage.require('vu')

    dir = File.expand_path(__FILE__).sub(/#{File.extname(__FILE__)}$/, '')

    autoload :Dial,          File.join(dir, 'dial')

    autoload :Pie,           File.join(dir, 'pie')
    autoload :PieSlice,      File.join(dir, 'pie')
    autoload :NamedPieSlice, File.join(dir, 'pie')

    autoload :Spinbox,       File.join(dir, 'spinbox')

    autoload :Bargraph,      File.join(dir, 'bargraph')
  end
end
