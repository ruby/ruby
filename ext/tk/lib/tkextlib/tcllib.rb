#
#  tcllib extension support
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# library directory
dir = File.expand_path(__FILE__).sub(/#{File.extname(__FILE__)}$/, '')

# call setup script
require File.join(dir, 'setup.rb')

# package:: autoscroll
#require 'tkextlib/tcllib/autoscroll'
require File.join(dir, 'autoscroll')

# package:: cursor
#require 'tkextlib/tcllib/cursor'
require File.join(dir, 'cursor')

# package:: style
#require 'tkextlib/tcllib/style'
require File.join(dir, 'style')


# autoload
module Tk
  module Tcllib
    dir = File.expand_path(__FILE__).sub(/#{File.extname(__FILE__)}$/, '')

    # package:: ctext
    #autoload :CText,      'tkextlib/tcllib/ctext'
    autoload :CText,      File.join(dir, 'ctext')

    # package:: datefield
    #autoload :Datefield,  'tkextlib/tcllib/datefield'
    #autoload :DateField,  'tkextlib/tcllib/datefield'
    autoload :Datefield,  File.join(dir, 'datefield')
    autoload :DateField,  File.join(dir, 'datefield')

    # package:: ipentry
    #autoload :IP_Entry,   'tkextlib/tcllib/ip_entry'
    autoload :IP_Entry,   File.join(dir, 'ip_entry')

    # package:: Plotchart
    #autoload :Plotchart,  'tkextlib/tcllib/plotchart'
    autoload :Plotchart,  File.join(dir, 'plotchart')

    # package:: tkpiechart
    #autoload :Tkpiechart, 'tkextlib/tcllib/tkpiechart'
    autoload :Tkpiechart, File.join(dir, 'tkpiechart')
  end
end
