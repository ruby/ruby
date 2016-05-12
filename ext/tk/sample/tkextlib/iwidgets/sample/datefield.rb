#!/usr/bin/env ruby
# frozen_string_literal: false
require 'tk'
require 'tkextlib/iwidgets'

df = Tk::Iwidgets::Datefield.new(:command=>proc{puts(df.get)})
df.pack(:fill=>:x, :expand=>true, :padx=>10,  :pady=>10)

Tk.mainloop
