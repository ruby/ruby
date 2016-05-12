#!/usr/bin/env ruby
# frozen_string_literal: false
#########################################################
#
#  set Tk.encoding = 'utf-8' for a utf8 character
#
#########################################################
require 'tk'
require 'tkextlib/iwidgets'

Tk.encoding = 'utf-8'

TkOption.add('*textBackground', 'white')

ef  = Tk::Iwidgets::Entryfield.new(:command=>proc{puts "Return Pressed"})

fef = Tk::Iwidgets::Entryfield.new(:labeltext=>'Fixed:',
                                   :fixed=>10, :width=>12)

nef = Tk::Iwidgets::Entryfield.new(:labeltext=>'Numeric:',
                                   :validate=>:numeric, :width=>12)

aef = Tk::Iwidgets::Entryfield.new(:labeltext=>'Alphabetic:',
                                   :validate=>:alphabetic, :width=>12,
                                   :invalid=>proc{
                                     puts "Alphabetic contents invalid"
                                   })

pef = Tk::Iwidgets::Entryfield.new(:labeltext=>'Password:', :width=>12,
                                   :show=>"\267",  ## <=== utf8 character
                                   :command=>proc{puts "Return Pressed"})

Tk::Iwidgets::Labeledwidget.alignlabels(ef, fef, nef, aef, pef)

ef.pack(:fil=>:x,  :expand=>true, :padx=>10, :pady=>5)
fef.pack(:fil=>:x,  :expand=>true, :padx=>10, :pady=>5)
nef.pack(:fil=>:x,  :expand=>true, :padx=>10, :pady=>5)
aef.pack(:fil=>:x,  :expand=>true, :padx=>10, :pady=>5)
pef.pack(:fil=>:x,  :expand=>true, :padx=>10, :pady=>5)

Tk.mainloop
