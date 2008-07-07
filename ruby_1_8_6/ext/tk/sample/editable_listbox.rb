#
# Editable_TkListbox class
#
#   When "DoubleClick-1" on a listbox item, the entry box is opend on the
#   item. And when hit "Return" key on the entry box after modifying the
#   text, the entry box is closed and the item is changed. Or when hit 
#   "Escape" key, the entry box is closed without modification.
#
#                              by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

class Editable_TkListbox < TkListbox
  def _ebox_placer(coord_y)
    idx = self.nearest(coord_y)
    x, y, w, h = self.bbox(idx)
    @ebox.place(:x => 0, :relwidth => 1.0, 
                :y => y - self.selectborderwidth, 
                :height => h + 2 * self.selectborderwidth)
    @ebox.pos = idx
    @ebox.value = self.listvariable.list[idx]
    @ebox.focus
  end
  private :_ebox_placer


  def create_self(keys)
    super(keys)

    unless self.listvariable
      self.listvariable = TkVariable.new(self.get(0, :end))
    end

    @ebox = TkEntry.new(self){
      @pos = -1
      def self.pos; @pos; end
      def self.pos=(idx); @pos = idx; end
    }

    @ebox.bind('Return'){
      list = self.listvariable.list
      list[@ebox.pos] = @ebox.value
      self.listvariable.value = list
      @ebox.place_forget
      @ebox.pos = -1
    }

    @ebox.bind('Escape'){
      @ebox.place_forget
      @ebox.pos = -1
    }

    self.bind('Double-1', '%y'){|y| _ebox_placer(y) }
  end
end

if $0 == __FILE__
  scr = TkScrollbar.new.pack(:side=>:right, :fill=>:y)

  lbox1 = Editable_TkListbox.new.pack(:side=>:left)
  lbox2 = Editable_TkListbox.new.pack(:side=>:left)

  scr.assign(lbox1, lbox2)

  lbox1.insert(:end, *%w(a b c d e f g h i j k l m n))
  lbox2.insert(:end,     0,1,2,3,4,5,6,7,8,9,0,1,2,3)

  Tk.mainloop
end
