#
#  autoload
#

#######################
#  geometry manager
autoload :TkGrid,             'tk/grid'
def TkGrid(*args); TkGrid.configure(*args); end

autoload :TkPack,             'tk/pack'
def TkPack(*args); TkPack.configure(*args); end

autoload :TkPlace,            'tk/place'
def TkPlace(*args); TkPlace.configure(*args); end


#######################
# others
autoload :TkBgError,          'tk/bgerror'

autoload :TkBindTag,          'tk/bindtag'
autoload :TkBindTagAll,       'tk/bindtag'
autoload :TkDatabaseClass,    'tk/bindtag'

autoload :TkButton,           'tk/button'

autoload :TkConsole,          'tk/console'

autoload :TkCanvas,           'tk/canvas'

autoload :TkcTagAccess,       'tk/canvastag'
autoload :TkcTag,             'tk/canvastag'
autoload :TkcTagString,       'tk/canvastag'
autoload :TkcNamedTag,        'tk/canvastag'
autoload :TkcTagAll,          'tk/canvastag'
autoload :TkcTagCurrent,      'tk/canvastag'
autoload :TkcTagGroup,        'tk/canvastag'

autoload :TkCheckButton,      'tk/checkbutton'
autoload :TkCheckbutton,      'tk/checkbutton'

autoload :TkClipboard,        'tk/clipboard'

autoload :TkComposite,        'tk/composite'

autoload :TkConsole,          'tk/console'

autoload :TkDialog,           'tk/dialog'
autoload :TkDialog2,          'tk/dialog'
autoload :TkWarning,          'tk/dialog'
autoload :TkWarning2,         'tk/dialog'

autoload :TkEntry,            'tk/entry'

autoload :TkEvent,            'tk/event'

autoload :TkFont,             'tk/font'
autoload :TkTreatTagFont,     'tk/font'

autoload :TkFrame,            'tk/frame'

autoload :TkImage,            'tk/image'
autoload :TkBitmapImage,      'tk/image'
autoload :TkPhotoImage,       'tk/image'

autoload :TkItemConfigMethod, 'tk/itemconfig'

autoload :TkTreatItemFont,    'tk/itemfont'

autoload :TkKinput,           'tk/kinput'

autoload :TkLabel,            'tk/label'

autoload :TkLabelFrame,       'tk/labelframe'
autoload :TkLabelframe,       'tk/labelframe'

autoload :TkListbox,          'tk/listbox'

autoload :TkMacResource,      'tk/macpkg'

autoload :TkMenu,             'tk/menu'
autoload :TkMenuClone,        'tk/menu'
autoload :TkSystemMenu,       'tk/menu'
autoload :TkSysMenu_Help,     'tk/menu'
autoload :TkSysMenu_System,   'tk/menu'
autoload :TkSysMenu_Apple,    'tk/menu'
autoload :TkMenubutton,       'tk/menu'
autoload :TkOptionMenubutton, 'tk/menu'

autoload :TkMenubar,          'tk/menubar'

autoload :TkMenuSpec,         'tk/menuspec'

autoload :TkMessage,          'tk/message'

autoload :TkManageFocus,      'tk/mngfocus'

autoload :TkMsgCatalog,       'tk/msgcat'
autoload :TkMsgCat,           'tk/msgcat'

autoload :TkNamespace,        'tk/namespace'

autoload :TkOptionDB,         'tk/optiondb'
autoload :TkOption,           'tk/optiondb'
autoload :TkResourceDB,       'tk/optiondb'

autoload :TkPackage,          'tk/package'

autoload :TkPalette,          'tk/palette'

autoload :TkPanedWindow,      'tk/panedwindow'
autoload :TkPanedwindow,      'tk/panedwindow'

autoload :TkRadioButton,      'tk/radiobutton'
autoload :TkRadiobutton,      'tk/radiobutton'

autoload :TkRoot,             'tk/root'

autoload :TkScale,            'tk/scale'

autoload :TkScrollbar,        'tk/scrollbar'
autoload :TkXScrollbar,       'tk/scrollbar'
autoload :TkYScrollbar,       'tk/scrollbar'

autoload :TkScrollbox,        'tk/scrollbox'

autoload :TkSelection,        'tk/selection'

autoload :TkSpinbox,          'tk/spinbox'

autoload :TkTreatTagFont,     'tk/tagfont'

autoload :TkText,             'tk/text'

autoload :TkTextImage,        'tk/textimage'

autoload :TkTextMark,         'tk/textmark'
autoload :TkTextNamedMark,    'tk/textmark'
autoload :TkTextMarkInsert,   'tk/textmark'
autoload :TkTextMarkCurrent,  'tk/textmark'
autoload :TkTextMarkAnchor,   'tk/textmark'

autoload :TkTextTag,          'tk/texttag'
autoload :TkTextNamedTag,     'tk/texttag'
autoload :TkTextTagSel,       'tk/texttag'

autoload :TkTextWindow,       'tk/textwindow'

autoload :TkAfter,            'tk/timer'
autoload :TkTimer,            'tk/timer'

autoload :TkToplevel,         'tk/toplevel'

autoload :TkTextWin,          'tk/txtwin_abst'

autoload :TkValidation,       'tk/validation'

autoload :TkVariable,         'tk/variable'
autoload :TkVarAccess,        'tk/variable'

autoload :TkVirtualEvent,     'tk/virtevent'

autoload :TkWinfo,            'tk/winfo'

autoload :TkWinDDE,           'tk/winpkg'
autoload :TkWinRegistry,      'tk/winpkg'

autoload :TkXIM,              'tk/xim'


#######################
# sub-module of Tk
module Tk
  autoload :Clock,            'tk/clock'
  autoload :OptionObj,        'tk/optionobj'
  autoload :X_Scrollable,     'tk/scrollable'
  autoload :Y_Scrollable,     'tk/scrollable'
  autoload :Scrollable,       'tk/scrollable'
  autoload :Wm,               'tk/wm'

  autoload :ValidateConfigure,     'tk/validation'
  autoload :ItemValidateConfigure, 'tk/validation'

  autoload :EncodedString,    'tk/encodedstr'
  def Tk.EncodedString(str, enc = nil); Tk::EncodedString.new(str, enc); end

  autoload :BinaryString,     'tk/encodedstr'
  def Tk.BinaryString(str); Tk::BinaryString.new(str); end

  autoload :UTF8_String,      'tk/encodedstr'
  def Tk.UTF8_String(str); Tk::UTF8_String.new(str); end
end
