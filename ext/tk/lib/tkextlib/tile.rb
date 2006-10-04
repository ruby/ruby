#
#  Tile theme engin (tile widget set) support
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# library directory
require 'tkextlib/tile/setup.rb'

# load package
# TkPackage.require('tile', '0.4')
# TkPackage.require('tile', '0.6')
# TkPackage.require('tile', '0.7')
verstr = TkPackage.require('tile')
ver = verstr.split('.')
if ver[0].to_i == 0 && ver[1].to_i <= 4
  # version 0.4 or former
  module Tk
    module Tile
      USE_TILE_NAMESPACE = true
      USE_TTK_NAMESPACE  = false
      TILE_SPEC_VERSION_ID = 0
    end
  end
elsif ver[0].to_i == 0 && ver[1].to_i <= 6
  # version 0.5 -- version 0.6
  module Tk
    module Tile
      USE_TILE_NAMESPACE = true
      USE_TTK_NAMESPACE  = true
      TILE_SPEC_VERSION_ID = 5
    end
  end
else
  # version 0.7 or later
  module Tk
    module Tile
      USE_TILE_NAMESPACE = false
      USE_TTK_NAMESPACE  = true
      TILE_SPEC_VERSION_ID = 7
    end
  end
end

# autoload
module Tk
  module Tile
    TkComm::TkExtlibAutoloadModule.unshift(self)

    PACKAGE_NAME = 'tile'.freeze
    def self.package_name
      PACKAGE_NAME
    end

    def self.package_version
      begin
        TkPackage.require('tile')
      rescue
        ''
      end
    end

    def self.__Import_Tile_Widgets__!
      Tk.tk_call('namespace', 'import', '-force', 'ttk::*')
    end

    def self.load_images(imgdir, pat=TkComm::None)
      images = Hash[*TkComm.simplelist(Tk.tk_call('::tile::LoadImages', 
                                                  imgdir, pat))]
      images.keys.each{|k|
        images[k] = TkPhotoImage.new(:imagename=>images[k], 
                                     :without_creating=>true)
      }

      images
    end

    def self.style(*args)
      args.map!{|arg| TkComm._get_eval_string(arg)}.join('.')
    end

    module KeyNav
      def self.enableMnemonics(w)
        Tk.tk_call('::keynav::enableMnemonics', w)
      end
      def self.defaultButton(w)
        Tk.tk_call('::keynav::defaultButton', w)
      end
    end

    module Font
      Default      = 'TkDefaultFont'
      Text         = 'TkTextFont'
      Heading      = 'TkHeadingFont'
      Caption      = 'TkCaptionFont'
      Tooltip      = 'TkTooltipFont'

      Fixed        = 'TkFixedFont'
      Menu         = 'TkMenuFont'
      SmallCaption = 'TkSmallCaptionFont'
      Icon         = 'TkIconFont'
    end

    module ParseStyleLayout
      def _style_layout(lst)
        ret = []
        until lst.empty?
          sub = [lst.shift]
          keys = {}

          until lst.empty?
            if lst[0][0] == ?-
              k = lst.shift[1..-1]
              children = lst.shift 
              children = _style_layout(children) if children.kind_of?(Array)
              keys[k] = children
            else
              break
            end
          end

          sub << keys unless keys.empty?
          ret << sub
        end
        ret
      end
      private :_style_layout
    end

    module TileWidget
      include Tk::Tile::ParseStyleLayout

      def __val2ruby_optkeys  # { key=>proc, ... }
        # The method is used to convert a opt-value to a ruby's object.
        # When get the value of the option "key", "proc.call(value)" is called.
        super().update('style'=>proc{|v| _style_layout(list(v))})
      end
      private :__val2ruby_optkeys

      def instate(state, script=nil, &b)
        if script
          tk_send('instate', state, script)
        elsif b
          tk_send('instate', state, Proc.new(&b))
        else
          bool(tk_send('instate', state))
        end
      end

      def state(state=nil)
        if state
          tk_send('state', state)
        else
          list(tk_send('state'))
        end
      end

      def identify(x, y)
        ret = tk_send_without_enc('identify', x, y)
        (ret.empty?)? nil: ret
      end
    end

    ######################################

    autoload :TButton,       'tkextlib/tile/tbutton'
    autoload :Button,        'tkextlib/tile/tbutton'

    autoload :TCheckButton,  'tkextlib/tile/tcheckbutton'
    autoload :CheckButton,   'tkextlib/tile/tcheckbutton'
    autoload :TCheckbutton,  'tkextlib/tile/tcheckbutton'
    autoload :Checkbutton,   'tkextlib/tile/tcheckbutton'

    autoload :Dialog,        'tkextlib/tile/dialog'

    autoload :TEntry,        'tkextlib/tile/tentry'
    autoload :Entry,         'tkextlib/tile/tentry'

    autoload :TCombobox,     'tkextlib/tile/tcombobox'
    autoload :Combobox,      'tkextlib/tile/tcombobox'

    autoload :TFrame,        'tkextlib/tile/tframe'
    autoload :Frame,         'tkextlib/tile/tframe'

    autoload :TLabelframe,   'tkextlib/tile/tlabelframe'
    autoload :Labelframe,    'tkextlib/tile/tlabelframe'

    autoload :TLabel,        'tkextlib/tile/tlabel'
    autoload :Label,         'tkextlib/tile/tlabel'

    autoload :TMenubutton,   'tkextlib/tile/tmenubutton'
    autoload :Menubutton,    'tkextlib/tile/tmenubutton'

    autoload :TNotebook,     'tkextlib/tile/tnotebook'
    autoload :Notebook,      'tkextlib/tile/tnotebook'

    autoload :TPaned,        'tkextlib/tile/tpaned'
    autoload :Paned,         'tkextlib/tile/tpaned'

    autoload :TProgressbar,  'tkextlib/tile/tprogressbar'
    autoload :Progressbar,   'tkextlib/tile/tprogressbar'

    autoload :TRadioButton,  'tkextlib/tile/tradiobutton'
    autoload :RadioButton,   'tkextlib/tile/tradiobutton'
    autoload :TRadiobutton,  'tkextlib/tile/tradiobutton'
    autoload :Radiobutton,   'tkextlib/tile/tradiobutton'

    autoload :TScale,        'tkextlib/tile/tscale'
    autoload :Scale,         'tkextlib/tile/tscale'
    autoload :TProgress,     'tkextlib/tile/tscale'
    autoload :Progress,      'tkextlib/tile/tscale'

    autoload :TScrollbar,    'tkextlib/tile/tscrollbar'
    autoload :Scrollbar,     'tkextlib/tile/tscrollbar'

    autoload :TSeparator,    'tkextlib/tile/tseparator'
    autoload :Separator,     'tkextlib/tile/tseparator'

    autoload :TSquare,       'tkextlib/tile/tsquare'
    autoload :Square,        'tkextlib/tile/tsquare'

    autoload :Treeview,      'tkextlib/tile/treeview'

    autoload :Style,         'tkextlib/tile/style'
  end
end
