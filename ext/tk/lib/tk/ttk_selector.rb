#
#  ttk_selector
#
######################################
#  toplevel classes/modules
module Tk
  @TOPLEVEL_ALIAS_TABLE[:Ttk] = {
    :TkButton       => 'tkextlib/tile/tbutton',

    :TkCheckbutton  => 'tkextlib/tile/tcheckbutton',
    :TkCheckButton  => 'tkextlib/tile/tcheckbutton',

    # :TkDialog       => 'tkextlib/tile/dialog',

    :TkEntry        => 'tkextlib/tile/tentry',

    :TkCombobox     => 'tkextlib/tile/tcombobox',

    :TkFrame        => 'tkextlib/tile/tframe',

    :TkLabel        => 'tkextlib/tile/tlabel',

    :TkLabelframe   => 'tkextlib/tile/tlabelframe',
    :TkLabelFrame   => 'tkextlib/tile/tlabelframe',

    :TkMenubutton   => 'tkextlib/tile/tmenubutton',
    :TkMenuButton   => 'tkextlib/tile/tmenubutton',

    :TkNotebook     => 'tkextlib/tile/tnotebook',

    # :TkPaned        => 'tkextlib/tile/tpaned',
    :TkPanedwindow  => 'tkextlib/tile/tpaned',
    :TkPanedWindow  => 'tkextlib/tile/tpaned',

    :TkProgressbar  => 'tkextlib/tile/tprogressbar',

    :TkRadiobutton  => 'tkextlib/tile/tradiobutton',
    :TkRadioButton  => 'tkextlib/tile/tradiobutton',

    :TkScale        => 'tkextlib/tile/tscale',
    # :TkProgress     => 'tkextlib/tile/tscale',

    :TkScrollbar    => 'tkextlib/tile/tscrollbar',
    :TkXScrollbar   => 'tkextlib/tile/tscrollbar',
    :TkYScrollbar   => 'tkextlib/tile/tscrollbar',

    :TkSeparator    => 'tkextlib/tile/tseparator',

    :TkSizeGrip     => 'tkextlib/tile/sizegrip',
    :TkSizegrip     => 'tkextlib/tile/sizegrip',

    # :TkSquare       => 'tkextlib/tile/tsquare',

    :TkTreeview     => 'tkextlib/tile/treeview',
  }
  @TOPLEVEL_ALIAS_TABLE[:Tile] = @TOPLEVEL_ALIAS_TABLE[:Ttk]

  ################################################
  # register some Ttk widgets as default
  # (Ttk is a standard library on Tcl/Tk8.5+)
  @TOPLEVEL_ALIAS_TABLE[:Ttk].each{|sym, file|
    unless Object.autoload?(sym) || Object.const_defined?(sym)
      Object.autoload(sym, file)
    end
  }

  ################################################

  @TOPLEVEL_ALIAS_SETUP_PROC[:Tile] =
    @TOPLEVEL_ALIAS_SETUP_PROC[:Ttk] = proc{|mod|
    unless Tk.autoload?(:Tile) || Tk.const_defined?(:Tile)
      Object.autoload :Ttk, 'tkextlib/tile'
      Tk.autoload :Tile, 'tkextlib/tile'
    end
  }
end
