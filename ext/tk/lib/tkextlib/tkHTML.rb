#
#  TkHtml support
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# library directory
dir = File.expand_path(__FILE__).sub(/#{File.extname(__FILE__)}$/, '')

# call setup script
require File.join(dir, 'setup.rb')

# load library
require File.join(dir, 'htmlwidget')
