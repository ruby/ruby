#
#  tcllib extension support
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script
require 'tkextlib/tcllib/setup.rb'

# package:: autoscroll
require 'tkextlib/tcllib/autoscroll'

# package:: cursor
require 'tkextlib/tcllib/cursor'

# package:: style
require 'tkextlib/tcllib/style'


# autoload
module Tk
  module Tcllib
    # package:: ctext
    autoload :CText,      'tkextlib/tcllib/ctext'

    # package:: datefield
    autoload :Datefield,  'tkextlib/tcllib/datefield'
    autoload :DateField,  'tkextlib/tcllib/datefield'

    # package:: ipentry
    autoload :IP_Entry,   'tkextlib/tcllib/ip_entry'

    # package:: Plotchart
    autoload :Plotchart,  'tkextlib/tcllib/plotchart'

    # package:: tkpiechart
    autoload :Tkpiechart, 'tkextlib/tcllib/tkpiechart'
  end
end
