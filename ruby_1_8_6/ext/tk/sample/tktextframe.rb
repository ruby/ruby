#
#  tktextframe.rb : a sample of TkComposite
#
#                         by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

class TkTextFrame < TkText
  include TkComposite

  def initialize_composite(keys={})
    keys = _symbolkey2str(keys)

    # create scrollbars
    @v_scroll = TkScrollbar.new(@frame, 'orient'=>'vertical')
    @h_scroll = TkScrollbar.new(@frame, 'orient'=>'horizontal')

    # create a text widget
    @text = TkText.new(@frame, 'wrap'=>'none')

    # set default receiver of method calls
    @path = @text.path

    # assign scrollbars
    @text.xscrollbar(@h_scroll)
    @text.yscrollbar(@v_scroll)

    # allignment
    TkGrid.rowconfigure(@frame, 0, 'weight'=>1, 'minsize'=>0)
    TkGrid.columnconfigure(@frame, 0, 'weight'=>1, 'minsize'=>0)
    @text.grid('row'=>0, 'column'=>0, 'sticky'=>'news')

    # scrollbars ON
    vscroll(keys.delete('vscroll'){true})
    hscroll(keys.delete('hscroll'){true})

    # set background of the text widget
=begin
    color = keys.delete('textbackground')
    textbackground(color) if color
=end
    # please check the differences of the following definitions
    option_methods(
       [:scrollbarwidth, :get_scrollbarwidth], 
       [:textbackground, nil, :textbg_info], 
       :textborderwidth, 
       :textrelief
    )

    # set receiver widgets for configure methods (with alias)
    delegate_alias('scrollbarrelief', 'relief', @h_scroll, @v_scroll)

    # set receiver widgets for configure methods
    delegate('DEFAULT', @text)
    delegate('background', @frame, @h_scroll, @v_scroll)
    delegate('activebackground', @h_scroll, @v_scroll)
    delegate('troughcolor', @h_scroll, @v_scroll)
    delegate('repeatdelay', @h_scroll, @v_scroll)
    delegate('repeatinterval', @h_scroll, @v_scroll)
    delegate('borderwidth', @frame)
    delegate('relief', @frame)

    # do configure
    configure keys unless keys.empty?
  end
  private :initialize_composite

  # set background color of text widget
  def textbackground(color = nil)
    if color
      @text.background(color)
    else
      @text.background
    end
  end

  def textbg_info
    info = @text.configinfo(:background)
    if TkComm::GET_CONFIGINFO_AS_ARRAY
      info[0] = 'textbackground'
      info
    else # ! TkComm::GET_CONFIGINFO_AS_ARRAY
      {'textbackground' => info['background']}
    end
  end

  # get/set borderwidth of text widget
  def set_textborderwidth(width)
    @text.borderwidth(width)
  end
  def get_textborderwidth
    @text.borderwidth
  end
  def textborderwidth(width = nil)
    if width
      set_textborderwidth(width)
    else
      get_textborderwidth
    end
  end

  # set relief of text widget
  def textrelief(type)
    @text.relief(type)
  end

  # get/set width of scrollbar
  def get_scrollbarwidth
    @v_scroll.width
  end
  def set_scrollbarwidth(width)
    @v_scroll.width(width)
    @h_scroll.width(width)
  end
  alias :scrollbarwidth :set_scrollbarwidth

  # vertical scrollbar : ON/OFF
  def vscroll(mode)
    st = TkGrid.info(@v_scroll)
    if mode && st.size == 0 then
      @v_scroll.grid('row'=>0, 'column'=>1, 'sticky'=>'ns')
    elsif !mode && st.size != 0 then
      @v_scroll.ungrid
    end
    self
  end

  # horizontal scrollbar : ON/OFF
  def hscroll(mode, wrap_mode="char")
    st = TkGrid.info(@h_scroll)
    if mode && st.size == 0 then
      @h_scroll.grid('row'=>1, 'column'=>0, 'sticky'=>'ew')
      wrap 'none'  # => self.wrap('none')
    elsif !mode && st.size != 0 then
      @h_scroll.ungrid
      wrap wrap_mode  # => self.wrap(wrap_mode)
    end
    self
  end
end


################################################
# test
################################################
if __FILE__ == $0
  f = TkFrame.new.pack('fill'=>'x')
  #t = TkTextFrame.new.pack
  t = TkTextFrame.new(:textborderwidth=>3, 
                      :textrelief=>:ridge, 
                      :scrollbarrelief=>:ridge).pack
  p t.configinfo
  TkButton.new(f, 'text'=>'vscr OFF', 
               'command'=>proc{t.vscroll(false)}).pack('side'=>'right')
  TkButton.new(f, 'text'=>'vscr ON', 
               'command'=>proc{t.vscroll(true)}).pack('side'=>'right')
  TkButton.new(f, 'text'=>'hscr ON', 
               'command'=>proc{t.hscroll(true)}).pack('side'=>'left')
  TkButton.new(f, 'text'=>'hscr OFF', 
               'command'=>proc{t.hscroll(false)}).pack('side'=>'left')
  Tk.mainloop
end
