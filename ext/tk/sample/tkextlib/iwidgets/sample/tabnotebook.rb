#!/usr/bin/env ruby
# frozen_string_literal: false
require 'tk'
require 'tkextlib/iwidgets'

# Create the tabnotebook widget and pack it.
tn = Tk::Iwidgets::Tabnotebook.new(:width=>300, :height=>100)
tn.pack(:anchor=>:nw, :fill=>:both, :expand=>true,
        :side=>:left, :padx=>10, :pady=>10)

# Add two pages to the tabnotebook,
# labelled "Page One" and "Page Two"
tn.add(:label=>'Page One')
tn.add(:label=>'Page Two')

# Get the child site frames of these two pages.
page1CS = tn.child_site(0)
page2CS = tn.child_site('Page Two')

# Create buttons on each page of the tabnotebook.
TkButton.new(page1CS, :text=>'Button One').pack
TkButton.new(page2CS, :text=>'Button Two').pack

# Select the first page of the tabnotebook.
tn.select(0)

Tk.mainloop
