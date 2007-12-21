#
#  autoload
#
major, minor, type, type_name, patchlevel = TclTkLib.get_version

######################################
#  depend on version of Tcl/Tk
if major > 8 || 
    (major == 8 && minor > 5) || 
    (major == 8 && minor == 5 && type >= TclTkLib::RELEASE_TYPE::BETA) 
  # Tcl/Tk 8.5 beta or later
  autoload :Ttk, 'tkextlib/tile'
  module Tk
    autoload :Tile, 'tkextlib/tile'
  end
end

######################################
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


######################################
# Ttk (Tile) support
require 'tk/ttk_selector'


######################################
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
  autoload :SystemMenu,       'tk/menu'
  autoload :SysMenu_Help,     'tk/menu'
  autoload :SysMenu_System,   'tk/menu'
  autoload :SysMenu_Apple,    'tk/menu'
  autoload :Menubutton,       'tk/menu'
  autoload :OptionMenubutton, 'tk/menu'

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


######################################
# sub-module of Tk
module Tk
  autoload :Clock,            'tk/clock'

  autoload :OptionObj,        'tk/optionobj'

  autoload :X_Scrollable,     'tk/scrollable'
  autoload :Y_Scrollable,     'tk/scrollable'
  autoload :Scrollable,       'tk/scrollable'

  autoload :Wm,               'tk/wm'

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

######################################
#  toplevel classes/modules
autoload_list = {
  :TkBgError            => 'tk/bgerror', 

  :TkBindTag            => 'tk/bindtag', 
  :TkBindTagAll         => 'tk/bindtag', 
  :TkDatabaseClass      => 'tk/bindtag', 

  :TkButton             => 'tk/button', 

  :TkCanvas             => 'tk/canvas', 

  :TkcItem              => 'tk/canvas', 
  :TkcArc               => 'tk/canvas', 
  :TkcBitmap            => 'tk/canvas', 
  :TkcImage             => 'tk/canvas', 
  :TkcLine              => 'tk/canvas', 
  :TkcOval              => 'tk/canvas', 
  :TkcPolygon           => 'tk/canvas', 
  :TkcRectangle         => 'tk/canvas', 
  :TkcText              => 'tk/canvas', 
  :TkcWindow            => 'tk/canvas', 

  :TkcTagAccess         => 'tk/canvastag', 
  :TkcTag               => 'tk/canvastag', 
  :TkcTagString         => 'tk/canvastag', 
  :TkcNamedTag          => 'tk/canvastag', 
  :TkcTagAll            => 'tk/canvastag', 
  :TkcTagCurrent        => 'tk/canvastag', 
  :TkcTagGroup          => 'tk/canvastag', 

  :TkCheckButton        => 'tk/checkbutton', 
  :TkCheckbutton        => 'tk/checkbutton', 

  :TkClipboard          => 'tk/clipboard', 

  :TkComposite          => 'tk/composite', 

  :TkConsole            => 'tk/console', 

  :TkDialog             => 'tk/dialog', 
  :TkDialog2            => 'tk/dialog', 
  :TkDialogObj          => 'tk/dialog', 
  :TkWarning            => 'tk/dialog', 
  :TkWarning2           => 'tk/dialog', 
  :TkWarningObj         => 'tk/dialog', 

  :TkEntry              => 'tk/entry', 

  :TkEvent              => 'tk/event', 

  :TkFont               => 'tk/font', 
  :TkTreatTagFont       => 'tk/font', 

  :TkFrame              => 'tk/frame', 

  :TkImage              => 'tk/image', 
  :TkBitmapImage        => 'tk/image', 
  :TkPhotoImage         => 'tk/image', 

  :TkItemConfigMethod   => 'tk/itemconfig', 

  :TkTreatItemFont      => 'tk/itemfont', 

  :TkKinput             => 'tk/kinput', 

  :TkLabel              => 'tk/label', 

  :TkLabelFrame         => 'tk/labelframe', 
  :TkLabelframe         => 'tk/labelframe', 

  :TkListbox            => 'tk/listbox', 

  :TkMacResource        => 'tk/macpkg', 

  :TkMenu               => 'tk/menu', 
  :TkMenuClone          => 'tk/menu', 
  :TkSystemMenu         => 'tk/menu', 
  :TkSysMenu_Help       => 'tk/menu', 
  :TkSysMenu_System     => 'tk/menu', 
  :TkSysMenu_Apple      => 'tk/menu', 
  :TkMenubutton         => 'tk/menu', 
  :TkOptionMenubutton   => 'tk/menu', 

  :TkMenubar            => 'tk/menubar', 

  :TkMenuSpec           => 'tk/menuspec', 

  :TkMessage            => 'tk/message', 

  :TkManageFocus        => 'tk/mngfocus', 

  :TkMsgCatalog         => 'tk/msgcat', 
  :TkMsgCat             => 'tk/msgcat', 

  :TkNamespace          => 'tk/namespace', 

  :TkOptionDB           => 'tk/optiondb', 
  :TkOption             => 'tk/optiondb', 
  :TkResourceDB         => 'tk/optiondb', 

  :TkPackage            => 'tk/package', 

  :TkPalette            => 'tk/palette', 

  :TkPanedWindow        => 'tk/panedwindow', 
  :TkPanedwindow        => 'tk/panedwindow', 

  :TkRadioButton        => 'tk/radiobutton', 
  :TkRadiobutton        => 'tk/radiobutton', 

  :TkRoot               => 'tk/root', 

  :TkScale              => 'tk/scale', 

  :TkScrollbar          => 'tk/scrollbar', 
  :TkXScrollbar         => 'tk/scrollbar', 
  :TkYScrollbar         => 'tk/scrollbar', 

  :TkScrollbox          => 'tk/scrollbox', 

  :TkSelection          => 'tk/selection', 

  :TkSpinbox            => 'tk/spinbox', 

  :TkTreatTagFont       => 'tk/tagfont', 

  :TkText               => 'tk/text', 

  :TkTextImage          => 'tk/textimage', 
  :TktImage             => 'tk/textimage', 

  :TkTextMark           => 'tk/textmark', 
  :TkTextNamedMark      => 'tk/textmark', 
  :TkTextMarkInsert     => 'tk/textmark', 
  :TkTextMarkCurrent    => 'tk/textmark', 
  :TkTextMarkAnchor     => 'tk/textmark', 
  :TktMark              => 'tk/textmark', 
  :TktNamedMark         => 'tk/textmark', 
  :TktMarkInsert        => 'tk/textmark', 
  :TktMarkCurrent       => 'tk/textmark', 
  :TktMarkAnchor        => 'tk/textmark', 

  :TkTextTag            => 'tk/texttag', 
  :TkTextNamedTag       => 'tk/texttag', 
  :TkTextTagSel         => 'tk/texttag', 
  :TktTag               => 'tk/texttag', 
  :TktNamedTag          => 'tk/texttag', 
  :TktTagSel            => 'tk/texttag', 

  :TkTextWindow         => 'tk/textwindow', 
  :TktWindow           => 'tk/textwindow', 

  :TkAfter              => 'tk/timer', 
  :TkTimer              => 'tk/timer', 
  :TkRTTimer            => 'tk/timer', 

  :TkToplevel           => 'tk/toplevel', 

  :TkTextWin            => 'tk/txtwin_abst', 

  :TkValidation         => 'tk/validation', 

  :TkVariable           => 'tk/variable', 
  :TkVarAccess          => 'tk/variable', 

  :TkVirtualEvent       => 'tk/virtevent', 
  :TkNamedVirtualEvent  => 'tk/virtevent', 

  :TkWinfo              => 'tk/winfo', 

  :TkWinDDE             => 'tk/winpkg', 
  :TkWinRegistry        => 'tk/winpkg', 

  :TkXIM                => 'tk/xim', 
}
autoload_list.each{|mod, lib|
  #autoload mod, lib unless 
  autoload mod, lib unless (Object.const_defined? mod) && (autoload? mod)
}
