#
#		tkclass.rb - Tk classes
#			$Date: 1995/11/11 19:17:15 $
#			by Yukihiro Matsumoto <matz@caelum.co.jp>

require "tk"

TopLevel = TkToplevel
Frame = TkFrame
Label = TkLabel
Button = TkButton
Radiobutton = TkRadioButton
Checkbutton = TkCheckButton
Message = TkMessage
Entry = TkEntry
Text = TkText
Scale = TkScale
Scrollbar = TkScrollbar
Listbox = TkListbox
Menu = TkMenu
Menubutton = TkMenubutton
Canvas = TkCanvas
Arc = TkcArc
Bitmap = TkcBitmap
Line = TkcLine
Oval = TkcOval
Polygon = TkcPolygon
Rectangle = TkcRectangle
TextItem = TkcText
WindowItem = TkcWindow
Selection = TkSelection
Winfo = TkWinfo
Pack = TkPack
Variable = TkVariable

def Mainloop
  Tk.mainloop
end
