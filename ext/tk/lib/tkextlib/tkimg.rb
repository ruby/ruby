#
#  TkImg extension support
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# library directory
dir = File.expand_path(__FILE__).sub(/#{File.extname(__FILE__)}$/, '')

# call setup script
require File.join(dir, 'setup.rb')

# load all image format handlers
#TkPackage.require('Img', '1.3')
TkPackage.require('Img')

# autoload
#autoload :TkPixmapImage, 'tkextlib/tkimg/pixmap'
autoload :TkPixmapImage, File.join(dir, 'pixmap')
