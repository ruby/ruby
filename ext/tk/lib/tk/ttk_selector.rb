#
#  ttk_selector
#
module Ttk_Selector
  @TTK_CLASS_NAMES = {}

  def self.use_ttk_as_default(mode = true)
    if mode # Use Ttk widgets
      @TTK_CLASS_NAMES.each{|name, status|
        eval("::Tk#{name} = ::Tk::#{(status)? 'Tile::': '::'}#{name}", 
             TOPLEVEL_BINDING)
      }
    else # Use standard Tk widagets
      @TTK_CLASS_NAMES.each{|name, status|
        eval("::Tk#{name} = ::Tk::#{name}", TOPLEVEL_BINDING)
      }
    end
  end

  def self.add(name)
    @TTK_CLASS_NAMES[name] = true
  end

  def self.remove(name)
    @TTK_CLASS_NAMES[name] = false
  end
end

#--------------------------------------------------------------------

Ttk_Selector.add('Button')
Ttk_Selector.add('Checkbutton')
Ttk_Selector.add('Entry')
##(ttk only)  Ttk_Selector.add('Combobox')
##(ttk only)  Ttk_Selector.add('Dialog')
Ttk_Selector.add('Frame')
Ttk_Selector.add('Label')
Ttk_Selector.add('Labelframe')
##(std only)  Ttk_Selector.add('Listbox')
Ttk_Selector.add('Menubutton')
##(ttk only)  Ttk_Selector.add('Notebook')
Ttk_Selector.add('Panedwindow')
##(ttk only)  Ttk_Selector.add('Progressbar')
Ttk_Selector.add('Radiobutton')
Ttk_Selector.add('Scale')
##(ttk only)  Ttk_Selector.add('Progress')
Ttk_Selector.add('Scrollbar')
Ttk_Selector.add('XScrollbar')
Ttk_Selector.add('YScrollbar')
##(ttk only)  Ttk_Selector.add('Separator')
##(ttk only)  Ttk_Selector.add('SizeGrip')
##(ttk only)  Ttk_Selector.add('Square')
##(ttk only)  Ttk_Selector.add('Treeview')

#--------------------------------------------------------------------
