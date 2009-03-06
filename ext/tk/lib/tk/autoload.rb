#
#  autoload
#
############################################
#  geometry manager
module Tk
  autoload :Grid,             'tk/grid'
  def Grid(*args); TkGrid.configure(*args); end

  autoload :Pack,             'tk/pack'
  def Pack(*args); TkPack.configure(*args); end

  autoload :Place,            'tk/place'
  def Place(*args); TkPlace.configure(*args); end
end

autoload :TkGrid,             'tk/grid'
def TkGrid(*args); TkGrid.configure(*args); end

autoload :TkPack,             'tk/pack'
def TkPack(*args); TkPack.configure(*args); end

autoload :TkPlace,            'tk/place'
def TkPlace(*args); TkPlace.configure(*args); end


############################################
# classes on Tk module
module Tk
  autoload :Button,           'tk/button'

  autoload :Canvas,           'tk/canvas'

  autoload :CheckButton,      'tk/checkbutton'
  autoload :Checkbutton,      'tk/checkbutton'

  autoload :Entry,            'tk/entry'

  autoload :Frame,            'tk/frame'

  autoload :Label,            'tk/label'

  autoload :LabelFrame,       'tk/labelframe'
  autoload :Labelframe,       'tk/labelframe'

  autoload :Listbox,          'tk/listbox'

  autoload :Menu,             'tk/menu'
  autoload :MenuClone,        'tk/menu'
  autoload :CloneMenu,        'tk/menu'
  autoload :SystemMenu,       'tk/menu'
  autoload :SysMenu_Help,     'tk/menu'
  autoload :SysMenu_System,   'tk/menu'
  autoload :SysMenu_Apple,    'tk/menu'
  autoload :Menubutton,       'tk/menu'
  autoload :MenuButton,       'tk/menu'
  autoload :OptionMenubutton, 'tk/menu'
  autoload :OptionMenBbutton, 'tk/menu'

  autoload :Message,          'tk/message'

  autoload :PanedWindow,      'tk/panedwindow'
  autoload :Panedwindow,      'tk/panedwindow'

  autoload :RadioButton,      'tk/radiobutton'
  autoload :Radiobutton,      'tk/radiobutton'

  autoload :Root,             'tk/root'

  autoload :Scale,            'tk/scale'

  autoload :Scrollbar,        'tk/scrollbar'
  autoload :XScrollbar,       'tk/scrollbar'
  autoload :YScrollbar,       'tk/scrollbar'

  autoload :Spinbox,          'tk/spinbox'

  autoload :Text,             'tk/text'

  autoload :Toplevel,         'tk/toplevel'
end


############################################
# sub-module of Tk
module Tk
  autoload :Clock,            'tk/clock'

  autoload :OptionObj,        'tk/optionobj'

  autoload :X_Scrollable,     'tk/scrollable'
  autoload :Y_Scrollable,     'tk/scrollable'
  autoload :Scrollable,       'tk/scrollable'

  autoload :Wm,               'tk/wm'
  autoload :Wm_for_General,   'tk/wm'

  autoload :MacResource,      'tk/macpkg'

  autoload :WinDDE,           'tk/winpkg'
  autoload :WinRegistry,      'tk/winpkg'

  autoload :ValidateConfigure,     'tk/validation'
  autoload :ItemValidateConfigure, 'tk/validation'

  autoload :EncodedString,    'tk/encodedstr'
  def Tk.EncodedString(str, enc = nil); Tk::EncodedString.new(str, enc); end

  autoload :BinaryString,     'tk/encodedstr'
  def Tk.BinaryString(str); Tk::BinaryString.new(str); end

  autoload :UTF8_String,      'tk/encodedstr'
  def Tk.UTF8_String(str); Tk::UTF8_String.new(str); end

end


############################################
#  toplevel classes/modules (fixed)
autoload :TkBgError,          'tk/bgerror'

autoload :TkBindTag,          'tk/bindtag'
autoload :TkBindTagAll,       'tk/bindtag'
autoload :TkDatabaseClass,    'tk/bindtag'

autoload :TkConsole,          'tk/console'

autoload :TkcItem,            'tk/canvas'
autoload :TkcArc,             'tk/canvas'
autoload :TkcBitmap,          'tk/canvas'
autoload :TkcImage,           'tk/canvas'
autoload :TkcLine,            'tk/canvas'
autoload :TkcOval,            'tk/canvas'
autoload :TkcPolygon,         'tk/canvas'
autoload :TkcRectangle,       'tk/canvas'
autoload :TkcText,            'tk/canvas'
autoload :TkcWindow,          'tk/canvas'

autoload :TkcTagAccess,       'tk/canvastag'
autoload :TkcTag,             'tk/canvastag'
autoload :TkcTagString,       'tk/canvastag'
autoload :TkcNamedTag,        'tk/canvastag'
autoload :TkcTagAll,          'tk/canvastag'
autoload :TkcTagCurrent,      'tk/canvastag'
autoload :TkcTagGroup,        'tk/canvastag'

autoload :TkClipboard,        'tk/clipboard'

autoload :TkComposite,        'tk/composite'

autoload :TkConsole,          'tk/console'

autoload :TkDialog,           'tk/dialog'
autoload :TkDialog2,          'tk/dialog'
autoload :TkDialogObj,        'tk/dialog'
autoload :TkWarning,          'tk/dialog'
autoload :TkWarning2,         'tk/dialog'
autoload :TkWarningObj,       'tk/dialog'

autoload :TkEvent,            'tk/event'

autoload :TkFont,             'tk/font'
autoload :TkNamedFont,        'tk/font'

autoload :TkImage,            'tk/image'
autoload :TkBitmapImage,      'tk/image'
autoload :TkPhotoImage,       'tk/image'

autoload :TkItemConfigMethod, 'tk/itemconfig'

autoload :TkTreatItemFont,    'tk/itemfont'

autoload :TkKinput,           'tk/kinput'

autoload :TkSystemMenu,       'tk/menu'

autoload :TkMenubar,          'tk/menubar'

autoload :TkMenuSpec,         'tk/menuspec'

autoload :TkManageFocus,      'tk/mngfocus'

autoload :TkMsgCatalog,       'tk/msgcat'
autoload :TkMsgCat,           'tk/msgcat'

autoload :TkNamespace,        'tk/namespace'

autoload :TkOptionDB,         'tk/optiondb'
autoload :TkOption,           'tk/optiondb'
autoload :TkResourceDB,       'tk/optiondb'

autoload :TkPackage,          'tk/package'

autoload :TkPalette,          'tk/palette'

autoload :TkRoot,             'tk/root'

autoload :TkScrollbox,        'tk/scrollbox'

autoload :TkSelection,        'tk/selection'

autoload :TkTreatTagFont,     'tk/tagfont'

autoload :TkTextImage,        'tk/textimage'
autoload :TktImage,           'tk/textimage'

autoload :TkTextMark,         'tk/textmark'
autoload :TkTextNamedMark,    'tk/textmark'
autoload :TkTextMarkInsert,   'tk/textmark'
autoload :TkTextMarkCurrent,  'tk/textmark'
autoload :TkTextMarkAnchor,   'tk/textmark'
autoload :TktMark,            'tk/textmark'
autoload :TktNamedMark,       'tk/textmark'
autoload :TktMarkInsert,      'tk/textmark'
autoload :TktMarkCurrent,     'tk/textmark'
autoload :TktMarkAnchor,      'tk/textmark'

autoload :TkTextTag,          'tk/texttag'
autoload :TkTextNamedTag,     'tk/texttag'
autoload :TkTextTagSel,       'tk/texttag'
autoload :TktTag,             'tk/texttag'
autoload :TktNamedTag,        'tk/texttag'
autoload :TktTagSel,          'tk/texttag'

autoload :TkTextWindow,       'tk/textwindow'
autoload :TktWindow,          'tk/textwindow'

autoload :TkAfter,            'tk/timer'
autoload :TkTimer,            'tk/timer'
autoload :TkRTTimer,          'tk/timer'

autoload :TkTextWin,          'tk/txtwin_abst'

autoload :TkValidation,       'tk/validation'
autoload :TkValidateCommand,  'tk/validation'

autoload :TkVariable,         'tk/variable'
autoload :TkVarAccess,        'tk/variable'

autoload :TkVirtualEvent,     'tk/virtevent'
autoload :TkNamedVirtualEvent,'tk/virtevent'

autoload :TkWinfo,            'tk/winfo'

autoload :TkXIM,              'tk/xim'


############################################
#  toplevel classes/modules (switchable)
module Tk
  @TOPLEVEL_ALIAS_TABLE = {}
  @TOPLEVEL_ALIAS_TABLE[:Tk] = {
    :TkButton             => 'tk/button',

    :TkCanvas             => 'tk/canvas',

    :TkCheckButton        => 'tk/checkbutton',
    :TkCheckbutton        => 'tk/checkbutton',

    # :TkDialog             => 'tk/dialog',
    # :TkDialog2            => 'tk/dialog',
    # :TkDialogObj          => 'tk/dialog',
    # :TkWarning            => 'tk/dialog',
    # :TkWarning2           => 'tk/dialog',
    # :TkWarningObj         => 'tk/dialog',

    :TkEntry              => 'tk/entry',

    :TkFrame              => 'tk/frame',

    :TkLabel              => 'tk/label',

    :TkLabelFrame         => 'tk/labelframe',
    :TkLabelframe         => 'tk/labelframe',

    :TkListbox            => 'tk/listbox',

    :TkMacResource        => 'tk/macpkg',

    :TkMenu               => 'tk/menu',
    :TkMenuClone          => 'tk/menu',
    :TkCloneMenu          => 'tk/menu',
    # :TkSystemMenu         => 'tk/menu',
    :TkSysMenu_Help       => 'tk/menu',
    :TkSysMenu_System     => 'tk/menu',
    :TkSysMenu_Apple      => 'tk/menu',
    :TkMenubutton         => 'tk/menu',
    :TkMenuButton         => 'tk/menu',
    :TkOptionMenubutton   => 'tk/menu',
    :TkOptionMenuButton   => 'tk/menu',

    :TkMessage            => 'tk/message',

    :TkPanedWindow        => 'tk/panedwindow',
    :TkPanedwindow        => 'tk/panedwindow',

    :TkRadioButton        => 'tk/radiobutton',
    :TkRadiobutton        => 'tk/radiobutton',

    # :TkRoot               => 'tk/root',

    :TkScale              => 'tk/scale',

    :TkScrollbar          => 'tk/scrollbar',
    :TkXScrollbar         => 'tk/scrollbar',
    :TkYScrollbar         => 'tk/scrollbar',

    :TkSpinbox            => 'tk/spinbox',

    :TkText               => 'tk/text',

    :TkToplevel           => 'tk/toplevel',

    :TkWinDDE             => 'tk/winpkg',
    :TkWinRegistry        => 'tk/winpkg',
  }

  @TOPLEVEL_ALIAS_OWNER = {}

  @TOPLEVEL_ALIAS_SETUP_PROC = {}

  @current_default_widget_set = nil
end


############################################
#  methods to control default widget set
############################################

class << Tk
  def default_widget_set
    @current_default_widget_set
  end

  def default_widget_set=(target)
    target = target.to_sym
    return target if target == @current_default_widget_set

    if (cmd = @TOPLEVEL_ALIAS_SETUP_PROC[target])
      cmd.call(target)
    end

    _replace_toplevel_aliases(target)
  end

  def __set_toplevel_aliases__(target, obj, *symbols)
    @TOPLEVEL_ALIAS_TABLE[target = target.to_sym] ||= {}
    symbols.each{|sym|
      @TOPLEVEL_ALIAS_TABLE[target][sym = sym.to_sym] = obj
      # if @current_default_widget_set == target
      if @TOPLEVEL_ALIAS_OWNER[sym] == target
        Object.class_eval{remove_const sym} if Object.const_defined?(sym)
        Object.const_set(sym, obj)
      end
    }
  end

  ###################################
  private
  def _replace_toplevel_aliases(target)
    # check already autoloaded
    if (table = @TOPLEVEL_ALIAS_TABLE[current = @current_default_widget_set])
      table.each{|sym, file|
        if !Object.autoload?(sym) && Object.const_defined?(sym) &&
            @TOPLEVEL_ALIAS_TABLE[current][sym].kind_of?(String)
          # autoload -> class
          @TOPLEVEL_ALIAS_TABLE[current][sym] = Object.const_get(sym)
        end
      }
    end

    # setup autoloads
    @TOPLEVEL_ALIAS_TABLE[target].each{|sym, file|
      Object.class_eval{remove_const sym} if Object.const_defined?(sym)
      if file.kind_of?(String)
        # file => autoload target file
        Object.autoload(sym, file)
      else
        # file => loaded class object
        Object.const_set(sym, file)
      end
      @TOPLEVEL_ALIAS_OWNER[sym] = target
    }

    # update current alias
    @current_default_widget_set = target
  end
end

############################################
# setup default widget set => :Tk
Tk.default_widget_set = :Tk


############################################
#  depend on the version of Tcl/Tk
# major, minor, type, patchlevel = TclTkLib.get_version

############################################
# Ttk (Tile) support
=begin
if major > 8 ||
    (major == 8 && minor > 5) ||
    (major == 8 && minor == 5 && type >= TclTkLib::RELEASE_TYPE::BETA)
  # Tcl/Tk 8.5 beta or later
  Object.autoload :Ttk, 'tkextlib/tile'
  Tk.autoload :Tile, 'tkextlib/tile'

  require 'tk/ttk_selector'
end
=end
Object.autoload :Ttk, 'tkextlib/tile'
Tk.autoload :Tile, 'tkextlib/tile'
require 'tk/ttk_selector'
