#
#  TkDND (Tk Drag & Drop Extension) support
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# library directory
dir = File.expand_path(__FILE__).sub(/#{File.extname(__FILE__)}$/, '')

# call setup script
require File.join(dir, 'setup.rb')

module Tk
  module TkDND
    dir = File.expand_path(__FILE__).sub(/#{File.extname(__FILE__)}$/, '')

    #autoload :DND,   'tkextlib/tkDND/tkdnd'
    #autoload :Shape, 'tkextlib/tkDND/shape'
    autoload :DND,   File.join(dir, 'tkdnd')
    autoload :Shape, File.join(dir, 'shape')
  end
end
