#!/usr/bin/env ruby
# frozen_string_literal: false
require 'tk'
require 'tkextlib/iwidgets'

mainloop = Thread.new{Tk.mainloop}

TkButton.new(:text=>'QUIT',
             :command=>proc{Tk.root.destroy}).pack(:padx=>10, :pady=>10)

Tk::Iwidgets::Selectiondialog.new.activate

mainloop.join
