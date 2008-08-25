#
#  tkalignbox.rb : align widgets with same width/height
# 
#                                            by Hidetoshi NAGAI
#
#  The box size depends on 'reqheight' and 'reqwidth' of contained widgets. 
#  If you want to give the box size when those requested sizes are 0, 
#  please set box.propagate = false (See the test routine at the tail of 
#  this file).

require 'tk'

class TkAlignBox < TkFrame
  def initialize(*args)
    if self.class == TkAlignBox
      fail RuntimeError, "TkAlignBox is an abstract class"
    end
    @padx = 0
    @pady = 0
    if args[-1].kind_of? Hash
      keys = _symbolkey2str(args.pop)
      @padx = keys.delete('padx') || 0
      @pady = keys.delete('pady') || 0
      args.push(keys)
    end
    super(*args)
    @max_width = 0
    @max_height = 0
    @propagate = true
    @widgets = []
  end

  def _set_framesize
    fail RuntimeError, "TkAlignBox is an abstract class"
  end
  private :_set_framesize

  def _place_config(widget, idx, cnt)
    fail RuntimeError, "TkAlignBox is an abstract class"
  end
  private :_place_config

  def align
    widgets = []
    @widgets.each{|w| widgets << w if w.winfo_exist?}
    @widgets = widgets
    cnt = @widgets.size.to_f
    @widgets.each_with_index{|w, idx| _place_config(w, idx, cnt)}
    @widgets = widgets
    _set_framesize if @propagate
    self
  end

  def add(*widgets)
    widgets.each{|w|
      unless w.kind_of? TkWindow
        fail RuntimeError, "#{w.inspect} is not a widget instance."
      end
      @widgets.delete(w)
      @widgets << w
      sz = w.winfo_reqwidth
      @max_width = sz if @max_width < sz
      sz = w.winfo_reqheight
      @max_height = sz if @max_height < sz
    }
    align
  end

  def <<(widget)
    add(widget)
  end

  def insert(idx, widget)
    unless widget.kind_of? TkWindow
      fail RuntimeError, "#{widget.inspect} is not a widget instance."
    end
    @widgets.delete(widget)
    @widgets[idx,0] = widget
    sz = widget.winfo_reqwidth
    @max_width = sz if @max_width < sz
    sz = widget.winfo_reqheight
    @max_height = sz if @max_height < sz
    align
  end

  def delete(idx)
    ret = @widgets.delete_at(idx)
    @req_size = 0
    @widget.each{|w|
      sz = w.winfo_reqwidth
      @max_width = sz if @max_width < sz
      sz = w.winfo_reqheight
      @max_height = sz if @max_height < sz
    }
    align
    ret
  end

  def padx(size = nil)
    if size
      @padx = size
      align
    else
      @padx
    end
  end

  def pady(size = nil)
    if size
      @pady = size
      align
    else
      @pady
    end
  end

  attr_accessor :propagate
end

class TkHBox < TkAlignBox
  def _set_framesize
    bd = self.borderwidth
    self.width((@max_width + 2*@padx) * @widgets.size + 2*bd)
    self.height(@max_height + 2*@pady + 2*bd)
  end
  private :_set_framesize

  def _place_config(widget, idx, cnt)
    widget.place_in(self, 
                    'relx'=>idx/cnt, 'x'=>@padx, 
                    'rely'=>0, 'y'=>@pady, 
                    'relwidth'=>1.0/cnt, 'width'=>-2*@padx, 
                    'relheight'=>1.0, 'height'=>-2*@pady)
  end
  private :_place_config
end
TkHLBox = TkHBox

class TkHRBox < TkHBox
  def _place_config(widget, idx, cnt)
    widget.place_in(self, 
                    'relx'=>(cnt - idx - 1)/cnt, 'x'=>@padx, 
                    'rely'=>0, 'y'=>@pady, 
                    'relwidth'=>1.0/cnt, 'width'=>-2*@padx, 
                    'relheight'=>1.0, 'height'=>-2*@pady)
  end
  private :_place_config
end

class TkVBox < TkAlignBox
  def _set_framesize
    bd = self.borderwidth
    self.width(@max_width + 2*@padx + 2*bd)
    self.height((@max_height + 2*@pady) * @widgets.size + 2*bd)
  end
  private :_set_framesize

  def _place_config(widget, idx, cnt)
    widget.place_in(self, 
                    'relx'=>0, 'x'=>@padx, 
                    'rely'=>idx/cnt, 'y'=>@pady, 
                    'relwidth'=>1.0, 'width'=>-2*@padx, 
                    'relheight'=>1.0/cnt, 'height'=>-2*@pady)
  end
  private :_place_config
end
TkVTBox = TkVBox

class TkVBBox < TkVBox
  def _place_config(widget, idx, cnt)
    widget.place_in(self, 
                    'relx'=>0, 'x'=>@padx, 
                    'rely'=>(cnt - idx - 1)/cnt, 'y'=>@pady, 
                    'relwidth'=>1.0, 'width'=>-2*@padx, 
                    'relheight'=>1.0/cnt, 'height'=>-2*@pady)
  end
  private :_place_config
end

################################################
# test
################################################
if __FILE__ == $0
  f = TkHBox.new(:borderwidth=>3, :relief=>'ridge').pack
  f.add(TkButton.new(f, :text=>'a'),
        TkButton.new(f, :text=>'aa', :font=>'Helvetica 16'),
        TkButton.new(f, :text=>'aaa'),
        TkButton.new(f, :text=>'aaaa'))

  f = TkHBox.new(:borderwidth=>3, :relief=>'ridge', 
                 :padx=>7, :pady=>3, :background=>'yellow').pack
  f.add(TkButton.new(f, :text=>'a'),
        TkButton.new(f, :text=>'aa', :font=>'Helvetica 16'),
        TkButton.new(f, :text=>'aaa'),
        TkButton.new(f, :text=>'aaaa'))

  f = TkVBox.new(:borderwidth=>5, :relief=>'groove').pack
  f.add(TkButton.new(f, :text=>'a'),
        TkButton.new(f, :text=>'aa', :font=>'Helvetica 30'),
        TkButton.new(f, :text=>'aaa'),
        TkButton.new(f, :text=>'aaaa'))

  f = TkHRBox.new(:borderwidth=>3, :relief=>'raised').pack(:fill=>:x)
  f.add(TkButton.new(f, :text=>'a'),
        TkButton.new(f, :text=>'aa'), 
        TkButton.new(f, :text=>'aaa'))

  f = TkVBBox.new(:borderwidth=>3, :relief=>'ridge').pack(:fill=>:x)
  f.propagate = false
  f.height 100
  f.add(TkFrame.new(f){|ff| 
          TkButton.new(ff, :text=>'a').pack(:pady=>4, :padx=>6, 
                                            :fill=>:both, :expand=>true)
        }, 
        TkFrame.new(f){|ff| 
          TkButton.new(ff, :text=>'aa').pack(:pady=>4, :padx=>6, 
                                             :fill=>:both, :expand=>true)
        }, 
        TkFrame.new(f){|ff| 
          TkButton.new(ff, :text=>'aaaa').pack(:pady=>4, :padx=>6, 
                                               :fill=>:both, :expand=>true)
        })

  Tk.mainloop
end
