#!/usr/bin/env ruby
require 'tk'
require 'tkextlib/iwidgets'

Tk::Iwidgets::Extfileselectionbox.new.pack(padx:10, pady:10,
                                           fill::both, expand:true)

Tk.mainloop
