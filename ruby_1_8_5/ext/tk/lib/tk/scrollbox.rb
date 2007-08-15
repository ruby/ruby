#
#               tk/scrollbox.rb - Tk Listbox with Scrollbar
#                                 as an example of Composite Widget
#                       $Date: 2004/10/11 04:51:07 $
#                       by Yukihiro Matsumoto <matz@netlab.co.jp>
#
require 'tk'
require 'tk/listbox'

class TkScrollbox<TkListbox
  include TkComposite
  def initialize_composite(keys=nil)
    list = TkListbox.new(@frame)
    scroll = TkScrollbar.new(@frame)
    @path = list.path

=begin
    list.configure 'yscroll', scroll.path+" set"
    list.pack 'side'=>'left','fill'=>'both','expand'=>'yes'
    scroll.configure 'command', list.path+" yview"
    scroll.pack 'side'=>'right','fill'=>'y'
=end
    list.yscrollbar(scroll)
    list.pack('side'=>'left','fill'=>'both','expand'=>'yes')
    scroll.pack('side'=>'right','fill'=>'y')

    delegate('DEFAULT', list)
    delegate('foreground', list)
    delegate('background', list, scroll)
    delegate('borderwidth', @frame)
    delegate('relief', @frame)

    configure keys if keys
  end
  private :initialize_composite
end
