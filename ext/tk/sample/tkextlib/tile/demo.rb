#!/usr/bin/env ruby
#
# Demo for 'tile' package.
#
require 'tk'

demodir = File.dirname($0)
Tk::AUTO_PATH.lappend('.', demodir, File.join(demodir, 'themes'))

require 'tkextlib/tile'

Tk.load_tclscript(File.join(demodir, 'toolbutton.tcl'))

# This forces an update of the available packages list. It's required
# for package names to find the themes in demos/themes/*.tcl
Tk.tk_call(TkPackage.unknown_proc, 'Tcl', TkPackage.provide('Tcl'))

TkRoot.new{
  title 'Tile demo'
  iconname 'Tile demo'
}

# The descriptive names of the builtin themes.
$THEMELIST = [
  ['default', 'Classic'], 
  ['alt', 'Revitalized'], 
  ['winnative', 'Windows native'], 
  ['xpnative', 'XP Native'], 
  ['aqua', 'Aqua'], 
]

$V = TkVariable.new_hash(:THEME      => 'default', 
                         :COMPOUND   => 'top', 
                         :CONSOLE    => false, 
                         :MENURADIO1 => 'One', 
                         :MENUCHECK1 => true)

# Add in any available loadable themes.
TkPackage.names.find_all{|n| n =~ /^tile::theme::/}.each{|pkg|
  name = pkg.split('::')[-1]
  unless $THEMELIST.assoc(name)
    $THEMELIST << [name, Tk.tk_call('string', 'totitle', name)]
  end
}

# Add theme definition written by ruby
$RUBY_THEMELIST = []
begin
  load(File.join(demodir, 'themes', 'kroc.rb'), true)
rescue
  $RUBY_THEMELIST << ['kroc-rb', 'Kroc (by Ruby)', false]
else
  $RUBY_THEMELIST << ['kroc-rb', 'Kroc (by Ruby)', true]
end

def makeThemeControl(parent)
  c = Tk::Tile::TLabelframe.new(parent, :text=>'Theme')
  $THEMELIST.each{|theme, name|
    b = Tk::Tile::TRadiobutton.new(c, :text=>name, :value=>theme, 
                                   :variable=>$V.ref(:THEME), 
                                   :command=>proc{setTheme(theme)})
    b.grid(:sticky=>:ew)
    unless (TkPackage.names.find{|n| n == "tile::theme::#{theme}"})
      b.state(:disabled)
    end
  }
  $RUBY_THEMELIST.each{|theme, name, available|
    b = Tk::Tile::TRadiobutton.new(c, :text=>name, :value=>theme, 
                                   :variable=>$V.ref(:THEME), 
                                   :command=>proc{setTheme(theme)})
    b.grid(:sticky=>:ew)
    b.state(:disabled) unless available
  }
  c
end

def makeThemeMenu(parent)
  m = TkMenu.new(parent)
  $THEMELIST.each{|theme, name|
    m.add(:radiobutton, :label=>name, :variable=>$V.ref(:THEME), 
          :value=>theme, :command=>proc{setTheme(theme)})
    unless (TkPackage.names.find{|n| n == "tile::theme::#{theme}"})
      m.entryconfigure(:end, :state=>:disabled)
    end
  }
  $RUBY_THEMELIST.each{|theme, name, available|
    m.add(:radiobutton, :label=>name, :variable=>$V.ref(:THEME), 
          :value=>theme, :command=>proc{setTheme(theme)})
    m.entryconfigure(:end, :state=>:disabled) unless available
  }
  m
end

def setTheme(theme)
  if (TkPackage.names.find{|n| n == "tile::theme::#{theme}"})
    TkPackage.require("tile::theme::#{theme}")
  end
  Tk::Tile::Style.theme_use(theme)
end

#
# Load icons...
#
$BUTTONS = ['open', 'new', 'save']
$CHECKBOXES = ['bold', 'italic']
$ICON = {}

def loadIcons(file)
  Tk.load_tclscript(file)
  img_data = TkVarAccess.new('ImgData')
  img_data.keys.each{|icon|
    $ICON[icon] = TkPhotoImage.new(:data=>img_data[icon])
  }
end

loadIcons(File.join(demodir, 'iconlib.tcl'))

#
# Utilities:
#
def foreachWidget(wins, cmd)
  wins.each{|w|
    cmd.call(w)
    foreachWidget(w.winfo_children, cmd)
  }
end

# sbstub
#	Used as the :command option for a scrollbar,
#	updates the scrollbar's position.
#
def sbstub(sb, cmd, num, units = 'units')
  num = TkComm.number(num)
  case cmd.to_s
  when 'moveto'
    sb.set(num, num+0.5)

  when 'scroll'
    if units.to_s == 'pages'
      delta = 0.2
    else
      delta = 0.05
    end
    current = sb.get
    sb.set(current[0] + delta * num, current[1] + delta * num)
  end
end    

# ... for debugging:
TkBindTag::ALL.bind('ButtonPress-3', proc{|w| $W = w}, '%W')
TkBindTag::ALL.bind('Control-ButtonPress-3', proc{|w| w.set_focus}, '%W')

def showHelp()
  Tk.messageBox(:message=>'No help yet...')
end

#
# See toolbutton.tcl.
TkOption.add('*Toolbar.relief', :groove)
TkOption.add('*Toolbar.borderWidth', 2)

TkOption.add('*Toolbar.Button.Pad', 2)

$ROOT = Tk.root
$BASE = $ROOT
Tk.destroy(*($ROOT.winfo_children))

$TOOLBARS = []

#
# Toolbar button standard vs. tile comparison:
#
def makeToolbars
  #
  # Tile toolbar:
  #
  tb = Tk::Tile::TFrame.new($BASE, :class=>'Toolbar')
  $TOOLBARS << tb
  i = 0
  $BUTTONS.each{|icon|
    i += 1
    Tk::Tile::TButton.new(tb, :text=>icon, :image=>$ICON[icon], 
                          :compound=>$V[:COMPOUND], 
                          :style=>:Toolbutton).grid(:row=>0, :column=>i, 
                                                    :sticky=>:news)
  }
  $CHECKBOXES.each{|icon|
    i += 1
    Tk::Tile::TCheckbutton.new(tb, :text=>icon, :image=>$ICON[icon], 
                               :variable=>$V.ref(icon), 
                               :compound=>$V[:COMPOUND], 
                               :style=>:Toolbutton).grid(:row=>0, :column=>i, 
                                                         :sticky=>:news)
  }

  mb = Tk::Tile::TMenubutton.new(tb, :text=>'toolbar', :image=>$ICON['file'], 
                                 :compound=>$V[:COMPOUND])
  mb.configure(:menu=>makeCompoundMenu(mb))
  i += 1
  mb.grid(:row=>0, :column=>i, :sticky=>:news)

  i += 1
  tb.grid_columnconfigure(i, :weight=>1)

  #
  # Standard toolbar:
  #
  tb = TkFrame.new($BASE, :class=>'Toolbar')
  $TOOLBARS << tb
  i = 0
  $BUTTONS.each{|icon|
    i += 1
    TkButton.new(tb, :text=>icon, :image=>$ICON[icon], 
                 :compound=>$V[:COMPOUND], :relief=>:flat, 
                 :overrelief=>:raised).grid(:row=>0, :column=>i, 
                                            :sticky=>:news)
  }
  $CHECKBOXES.each{|icon|
    i += 1
    TkCheckbutton.new(tb, :text=>icon, :image=>$ICON[icon], 
                      :variable=>$V.ref(icon), :compound=>$V[:COMPOUND], 
                      :indicatoron=>false, :selectcolor=>'', :relief=>:flat, 
                      :overrelief=>:raised).grid(:row=>0, :column=>i, 
                                                 :sticky=>:news)
  }

  mb = TkMenubutton.new(tb, :text=>'toolbar', :image=>$ICON['file'], 
                        :compound=>$V[:COMPOUND])
  mb.configure(:menu=>makeCompoundMenu(mb))
  i += 1
  mb.grid(:row=>0, :column=>i, :sticky=>:news)

  i += 1
  tb.grid_columnconfigure(i, :weight=>1)
end

#
# Toolbar :compound control:
#
def makeCompoundMenu(mb)
  menu = TkMenu.new(mb)
  %w(text image none top bottom left right center).each{|str|
    menu.add(:radiobutton, :label=>Tk.tk_call('string', 'totitle', str), 
             :variable=>$V.ref(:COMPOUND), :value=>str, 
             :command=>proc{ changeToolbars() })
  }
  menu
end

makeToolbars()

## CONTROLS
control = Tk::Tile::TFrame.new($BASE)

#
# Overall theme control:
#
makeThemeControl(control).grid(:sticky=>:news, :padx=>6, :ipadx=>6)
control.grid_rowconfigure(99, :weight=>1)

def changeToolbars
  foreachWidget($TOOLBARS, 
                proc{|w|
                  begin
                    w.compound($V[:COMPOUND])
                  rescue
                  end
                })
end

def scrolledWidget(parent, klass, themed, *args)
  if themed
    f = Tk::Tile::TFrame.new(parent)
    t = klass.new(f, *args)
    vs = Tk::Tile::TScrollbar.new(f)
    hs = Tk::Tile::TScrollbar.new(f)
  else
    f = TkFrame.new(parent)
    t = klass.new(f, *args)
    vs = TkScrollbar.new(f)
    hs = TkScrollbar.new(f)
  end
  t.yscrollbar(vs)
  t.xscrollbar(hs)

  TkGrid.configure(t, vs, :sticky=>:news)
  TkGrid.configure(hs, 'x', :sticky=>:news)
  TkGrid.rowconfigure(f, 0, :weight=>1)
  TkGrid.columnconfigure(f, 0, :weight=>1)

  [f, t]
end

#
# Notebook demonstration:
#
def makeNotebook
  nb = Tk::Tile::TNotebook.new($BASE, :padding=>6)
  nb.enable_traversal
  client = Tk::Tile::TFrame.new(nb)
  nb.add(client, :text=>'Demo', :underline=>0)
  nb.select(client)

  others = Tk::Tile::TFrame.new(nb)
  nb.add(others, :text=>'Others', :underline=>4)
  nb.add(Tk::Tile::TLabel.new(nb, :text=>'Nothing to see here...'), 
         :text=>'Stuff', :sticky=>:new)
  nb.add(Tk::Tile::TLabel.new(nb, :text=>'Nothing to see here either.'), 
         :text=>'More Stuff', :sticky=>:se)

  [nb, client, others]
end

nb, client, others = makeNotebook()

#
# Side-by side check, radio, and menu button comparison:
#
def fillMenu(menu)
  %w(above below left right flush).each{|dir|
    menu.add(:command, :label=>Tk.tk_call('string', 'totitle', dir), 
             :command=>proc{ menu.winfo_parent.direction(dir) })
  }
  menu.add(:cascade, :label=>'Submenu', :menu=>(submenu = TkMenu.new(menu)))
  submenu.add(:command, :label=>'Subcommand 1')
  submenu.add(:command, :label=>'Subcommand 2')
  submenu.add(:command, :label=>'Subcommand 3')

  menu.add(:separator)
  menu.add(:command, :label=>'Quit', :command=>proc{Tk.root.destroy})
end

l = Tk::Tile::TLabelframe.new(client, :text=>'Styled', :padding=>6)
r = TkLabelframe.new(client, :text=>'Standard', :padx=>6, :pady=>6)

## Styled frame
cb = Tk::Tile::TCheckbutton.new(l, :text=>'Checkbutton', 
                                :variable=>$V.ref(:SELECTED), :underline=>2)
rb1 = Tk::Tile::TRadiobutton.new(l, :text=>'One', :variable=>$V.ref(:CHOICE), 
                                 :value=>1, :underline=>0)
rb2 = Tk::Tile::TRadiobutton.new(l, :text=>'Two', :variable=>$V.ref(:CHOICE), 
                                 :value=>2)
rb3 = Tk::Tile::TRadiobutton.new(l, :text=>'Three', 
                                 :variable=>$V.ref(:CHOICE), 
                                 :value=>3, :underline=>0)
btn = Tk::Tile::TButton.new(l, :text=>'Button', :underline=>0)

mb = Tk::Tile::TMenubutton.new(l, :text=>'Menubutton', :underline=>2)
#m = TkMenu.new(mb)
#mb.menu(m)
#fillMenu(m)

$entryText = TkVariable.new('Entry widget')
e = Tk::Tile::TEntry.new(l, :textvariable=>$entryText)
e.selection_range(6, :end)

ltext_f, ltext = scrolledWidget(l, TkText, true, 
                                :width=>12, :height=>5, :wrap=>:none)

scales = Tk::Tile::TFrame.new(l)
sc = Tk::Tile::TScale.new(scales, :orient=>:horizontal, :from=>0, :to=>100, 
                          :variable=>$V.ref(:SCALE))
vsc = Tk::Tile::TScale.new(scales, :orient=>:vertical, :from=>-25, :to=>25,  
                           :variable=>$V.ref(:VSCALE))

prg = Tk::Tile::TProgress.new(scales, :orient=>:horizontal, 
                              :from=>0, :to=>100)
vprg = Tk::Tile::TProgress.new(scales, :orient=>:vertical, 
                               :from=>-25, :to=>25)

sc.command{|*args| prg.set(*args)}
vsc.command{|*args| vprg.set(*args)}

Tk.grid(sc, :columnspan=>2, :sticky=>:ew)
Tk.grid(prg, :columnspan=>2, :sticky=>:ew)
Tk.grid(vsc, vprg, :sticky=>:nws)
TkGrid.columnconfigure(scales, 0, :weight=>1)
TkGrid.columnconfigure(scales, 1, :weight=>1)

# NOTE TO MAINTAINERS: 
# The checkbuttons are -sticky ew / -expand x  on purpose:
# it demonstrates one of the differences between TCheckbuttons
# and standard checkbuttons.
#
Tk.grid(cb, :sticky=>:ew)
Tk.grid(rb1, :sticky=>:ew)
Tk.grid(rb2, :sticky=>:ew)
Tk.grid(rb3, :sticky=>:ew)
Tk.grid(btn, :sticky=>:ew, :padx=>2, :pady=>2)
Tk.grid(mb, :sticky=>:ew, :padx=>2, :pady=>2)
Tk.grid(e, :sticky=>:ew, :padx=>2, :pady=>2)
Tk.grid(ltext_f, :sticky=>:news)
Tk.grid(scales, :sticky=>:news, :pady=>2)

TkGrid.columnconfigure(l, 0, :weight=>1)
TkGrid.rowconfigure(l, 7, :weight=>1) # text widget (grid is a PITA)

## Orig frame
cb = TkCheckbutton.new(r, :text=>'Checkbutton', :variable=>$V.ref(:SELECTED))
rb1 = TkRadiobutton.new(r, :text=>'One', 
                        :variable=>$V.ref(:CHOICE), :value=>1)
rb2 = TkRadiobutton.new(r, :text=>'Two', :variable=>$V.ref(:CHOICE), 
                        :value=>2, :underline=>1)
rb3 = TkRadiobutton.new(r, :text=>'Three', 
                        :variable=>$V.ref(:CHOICE), :value=>3)
btn = TkButton.new(r, :text=>'Button')

mb = TkMenubutton.new(r, :text=>'Menubutton', :underline=>3, :takefocus=>true)
m = TkMenu.new(mb)
mb.menu(m)
$V[:rmbIndicatoron] = mb.indicatoron
m.add(:checkbutton, :label=>'Indicator?', #'
      :variable=>$V.ref(:rmbIndicatoron), 
      :command=>proc{mb.indicatoron($V[:rmbIndicatoron])})
m.add(:separator)
fillMenu(m)

e = TkEntry.new(r, :textvariable=>$entryText)

rtext_f, rtext = scrolledWidget(r, TkText, false, 
                                :width=>12, :height=>5, :wrap=>:none)

sc = TkScale.new(r, :orient=>:horizontal, :from=>0, :to=>100, 
                 :variable=>$V.ref(:SCALE))
vsc = TkScale.new(r, :orient=>:vertical, :from=>-25, :to=>25,  
                  :variable=>$V.ref(:VSCALE))

Tk.grid(cb, :sticky=>:ew)
Tk.grid(rb1, :sticky=>:ew)
Tk.grid(rb2, :sticky=>:ew)
Tk.grid(rb3, :sticky=>:ew)
Tk.grid(btn, :sticky=>:ew, :padx=>2, :pady=>2)
Tk.grid(mb, :sticky=>:ew, :padx=>2, :pady=>2)
Tk.grid(e, :sticky=>:ew, :padx=>2, :pady=>2)
Tk.grid(rtext_f, :sticky=>:news)
Tk.grid(sc, :sticky=>:news)
Tk.grid(vsc, :sticky=>:nws)

TkGrid.columnconfigure(l, 0, :weight=>1)
TkGrid.rowconfigure(l, 7, :weight=>1) # text widget (grid is a PITA)

Tk.grid(l, r, :sticky=>:news, :padx=>6, :pady=>6)
TkGrid.rowconfigure(client, 0, :weight=>1)
TkGrid.columnconfigure(client, [0, 1], :weight=>1)

#
# Add some text to the text boxes:
#
msgs = [
"The cat crept into the crypt, crapped and crept out again", 
"Peter Piper picked a peck of pickled peppers", 
"How much wood would a woodchuck chuck if a woodchuck could chuck wood", 
"He thrusts his fists against the posts and still insists he sees the ghosts",
"Who put the bomb in the bom-b-bom-b-bom,",
"Is this your sister's sixth zither, sir?",
"Who put the ram in the ramalamadingdong?",
"I am not the pheasant plucker, I'm the pheasant plucker's mate."
]

nmsgs = msgs.size
(0...50).each{|n|
  msg = msgs[n % nmsgs]
  ltext.insert(:end, "#{n}: #{msg}\n")
  rtext.insert(:end, "#{n}: #{msg}\n")
}

#
# Command box:
#
cmd = Tk::Tile::TFrame.new($BASE)
b_close = Tk::Tile::TButton.new(cmd, :text=>'Close', 
                                :underline=>0, :default=>:normal, 
                                :command=>proc{Tk.root.destroy})
b_help = Tk::Tile::TButton.new(cmd, :text=>'Help', :underline=>0, 
                               :default=>:normal, :command=>proc{showHelp()})
Tk.grid('x', b_close, b_help, :pady=>[6, 4], :padx=>4)
TkGrid.columnconfigure(cmd, 0, :weight=>1)

#
# Set up accelerators:
#
$ROOT.bind('KeyPress-Escape', proc{Tk.event_generate(b_close, '<Invoke>')})
$ROOT.bind('<Help>', proc{Tk.event_generate(b_help, '<Invoke>')})
Tk::Tile::KeyNav.enableMnemonics($ROOT)
Tk::Tile::KeyNav.defaultButton(b_help)

Tk.grid($TOOLBARS[0], '-', :sticky=>:ew)
Tk.grid($TOOLBARS[1], '-', :sticky=>:ew)
Tk.grid(control,      nb,  :sticky=>:news)
Tk.grid(cmd,          '-', :sticky=>:ew)
TkGrid.columnconfigure($ROOT, 1, :weight=>1)
TkGrid.rowconfigure($ROOT, 2, :weight=>1)

#
# Add a menu
#
menu = TkMenu.new($BASE)
$ROOT.menu(menu)
m_file = TkMenu.new(menu, :tearoff=>0)
menu.add(:cascade, :label=>'File', :underline=>0, :menu=>m_file)
m_file.add(:command, :label=>'Open', :underline=>0, 
           :compound=>:left, :image=>$ICON['open'])
m_file.add(:command, :label=>'Save', :underline=>0, 
           :compound=>:left, :image=>$ICON['save'])
m_file.add(:separator)
m_f_test = TkMenu.new(menu, :tearoff=>0)
m_file.add(:cascade, :label=>'Test submenu', :underline=>0, :menu=>m_f_test)
m_file.add(:checkbutton, :label=>'Text check', :underline=>5, 
           :variable=>$V.ref(:MENUCHECK1))
m_file.insert(:end, :separator)

if Tk.windowingsystem != 'x11'
  TkConsole.create
  m_file.insert(:end, :checkbutton, :label=>'Console', :underline=>5, 
                :variable=>$V.ref(:CONSOLE), :command=>proc{toggle_console()})
  def toggle_console
    if TkComm.bool($V[:CONSOLE])
      TkConsole.show
    else
      TkConsole.hide
    end
  end
end

m_file.add(:command, :label=>'Exit', :underline=>1, 
           :command=>proc{Tk.event_generate(b_close, '<Invoke>')})

%w(One Two Three Four).each{|lbl|
  m_f_test.add(:radiobutton, :label=>lbl, :variable=>$V.ref(:MENURADIO1))
}

# Add Theme menu.
#
menu.add(:cascade, :label=>'Theme', :underline=>3, 
         :menu=>makeThemeMenu(menu))

setTheme($V[:THEME])

#
# Other demos:
#
$Timers = {:StateMonitor=>nil, :FocusMonitor=>nil}

msg = TkMessage.new(others, :aspect=>200)

$Desc = {}

showDescription = TkBindTag.new
showDescription.bind('Enter', proc{|w| msg.text($Desc[w.path])}, '%W')
showDescription.bind('Leave', proc{|w| msg.text('')}, '%W')

[
  [ :trackStates, "Widget states...",  
    "Display/modify widget state bits" ], 

  [ :scrollbarResizeDemo,  "Scrollbar resize behavior...", 
    "Shows how Tile and standard scrollbars differ when they're sized too large" ], 

  [ :trackFocus, "Track keyboard focus..." , 
    "Display the name of the widget that currently has focus" ]
].each{|demo_cmd, label, description|
  b = Tk::Tile::TButton.new(others, :text=>label, 
                            :command=>proc{ self.__send__(demo_cmd) })
  $Desc[b.path] = description
  b.bindtags <<= showDescription

  b.pack(:side=>:top, :expand=>false, :fill=>:x, :padx=>6, :pady=>6)
}

msg.pack(:side=>:bottom, :expand=>true, :fill=>:both)


#
# Scrollbar resize demo:
#
$scrollbars = nil

def scrollbarResizeDemo
  if $scrollbars
    begin
      $scrollbars.destroy
    rescue
    end
  end
  $scrollbars = TkToplevel.new(:title=>'Scrollbars', :geometry=>'200x200')
  f = TkFrame.new($scrollbars, :height=>200)
  tsb = Tk::Tile::TScrollbar.new(f, :command=>proc{|*args| sbstub(tsb, *args)})
  sb = TkScrollbar.new(f, :command=>proc{|*args| sbstub(sb, *args)})
  Tk.grid(tsb, sb, :sticky=>:news)

  sb.set(0, 0.5)  # prevent backwards-compatibility mode for old SB

  f.grid_columnconfigure(0, :weight=>1)
  f.grid_columnconfigure(1, :weight=>1)
  f.grid_rowconfigure(0, :weight=>1)

  f.pack(:expand=>true, :fill=>:both)
end

#
# Track focus demo:
#
$FocusInf = TkVariable.new_hash
$focus = nil

def trackFocus
  if $focus
    begin
      $focus.destroy
    rescue
    end
  end
  $focus = TkToplevel.new(:title=>'Keyboard focus')
  i = 0
  [
    ["Focus widget:", :Widget], 
    ["Class:", :WidgetClass], 
    ["Next:", :WidgetNext], 
    ["Grab:", :Grab], 
    ["Status:", :GrabStatus]
  ].each{|label, var_index|
    Tk.grid(Tk::Tile::TLabel.new($focus, :text=>label, :anchor=>:e), 
            Tk::Tile::TLabel.new($focus, 
                                 :textvariable=>$FocusInf.ref(var_index), 
                                 :width=>40, :anchor=>:w, :relief=>:groove), 
            :sticky=>:ew)
    i += 1
  }
  $focus.grid_columnconfigure(1, :weight=>1)
  $focus.grid_rowconfigure(i, :weight=>1)

  $focus.bind('Destroy', proc{Tk.after_cancel($Timers[:FocusMonitor])})
  focusMonitor
end

def focusMonitor
  $FocusInf[:Widget] = focus_win = Tk.focus
  if focus_win
    $FocusInf[:WidgetClass] = focus_win.winfo_classname
    $FocusInf[:WidgetNext] = Tk.focus_next(focus_win)
  else
    $FocusInf[:WidgetClass] = $FocusInf[:WidgetNext] = ''
  end

  $FocusInf[:Grab] = grab_wins = Tk.current_grabs
  unless grab_wins.empty?
    $FocusInf[:GrabStatus] = grab_wins[0].grab_status
  else  
    $FocusInf[:GrabStatus] = ''
  end

  $Timers[:FocusMonitor] = Tk.after(200, proc{ focusMonitor() })
end

#
# Widget state demo:
#

$Widget = TkVariable.new

TkBindTag::ALL.bind('Control-Shift-ButtonPress-1', 
                    proc{|w|
                      $Widget.value = w
                      updateStates()
                      Tk.callback_break
                    }, '%W')
$states_list = %w(active disabled focus pressed selected 
                  background indeterminate invalid default)
$states_btns = {}
$states = nil

$State = TkVariable.new_hash

def trackStates
  if $states
    begin
      $state.destroy
    rescue
    end
  end
  $states = TkToplevel.new(:title=>'Widget states')

  l_inf = Tk::Tile::TLabel.new($states, :text=>"Press Control-Shift-Button-1 on any widget")

  l_lw = Tk::Tile::TLabel.new($states, :text=>'Widget:', 
                              :anchor=>:e, :relief=>:groove)
  l_w = Tk::Tile::TLabel.new($states, :textvariable=>$Widget, 
                              :anchor=>:w, :relief=>:groove)

  Tk.grid(l_inf, '-', :sticky=>:ew, :padx=>6, :pady=>6)
  Tk.grid(l_lw, l_w, :sticky=>:ew)

  $states_list.each{|st|
    cb = Tk::Tile::TCheckbutton.new($states, :text=>st, 
                                    :variable=>$State.ref(st), 
                                    :command=>proc{ changeState(st) })
    $states_btns[st] = cb
    Tk.grid('x', cb, :sticky=>:nsew)
  }

  $states.grid_columnconfigure(1, :weight=>1)

  f_cmd = Tk::Tile::TFrame.new($states)
  Tk.grid('x', f_cmd, :sticky=>:nse)

  b_close = Tk::Tile::TButton.new(f_cmd, :text=>'Close', 
                                  :command=>proc{ $states.destroy })
  Tk.grid('x', b_close, :padx=>4, :pady=>[6,4])
  f_cmd.grid_columnconfigure(0, :weight=>1)

  $states.bind('KeyPress-Escape', proc{Tk.event_generate(b_close, '<Invoke>')})

  $states.bind('Destroy', proc{Tk.after_cancel($Timers[:StateMonitor])})
  stateMonitor()
end

def stateMonitor
  updateStates() if $Widget.value != ''
  $Timers[:StateMonitor] = Tk.after(200, proc{ stateMonitor() })
end

def updateStates
  $states_list.each{|st|
    begin
      $State[st] = $Widget.window.instate(st)
    rescue
      $states_btns[st].state('disabled')
    else
      $states_btns[st].state('!disabled')
    end
  }
end

def changeState(st)
  if $Widget.value != ''
    if $State.bool_element(st)
      $Widget.window.state(st)
    else
      $Widget.window.state("!#{st}")
    end
  end
end

Tk.mainloop
