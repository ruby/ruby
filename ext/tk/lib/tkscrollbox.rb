#
#		tkscrollbox.rb - Tk Listbox with Scrollbar
#                                 as an example of Composite Widget
#			$Date$
#			by Yukihiro Matsumoto <matz@caelum.co.jp>

require 'tk.rb'

class TkScrollbox<TkListbox
  include TkComposite
  def initialize_composite
    list = TkListbox.new(@frame)
    scroll = TkScrollbar.new(@frame)
    @path = list.path

    list.configure 'yscroll', scroll.path+" set"
    list.pack 'side'=>'left','fill'=>'both','expand'=>'yes'
    scroll.configure 'command', list.path+" yview"
    scroll.pack 'side'=>'right','fill'=>'y'

    delegate('DEFAULT', list)
    delegate('foreground', list)
    delegate('background', list, scroll)
    delegate('borderwidth', @frame)
    delegate('relief', @frame)
  end
end
