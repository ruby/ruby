#!/usr/bin/env ruby
require 'tk'
require 'tkextlib/iwidgets'

def get_files(file)
  dir = (file.empty?)? ENV['HOME'] : file
  Dir.chdir(dir) rescue return ''
  rlist = []
  Dir['*'].sort.each{|f| rlist << File.join(dir, f) }
  rlist
end

Tk::Iwidgets::Hierarchy.new(:querycommand=>proc{|arg| get_files(arg.node)}, 
                            :visibleitems=>'30x15', 
                            :labeltext=>ENV['HOME']).pack(:side=>:left, 
                                                          :expand=>true, 
                                                          :fill=>:both)

# Tk::Iwidgets::Hierarchy.new(:querycommand=>[proc{|n| get_files(n)}, '%n'], 
#                           :visibleitems=>'30x15', 
#                           :labeltext=>ENV['HOME']).pack(:side=>:left, 
#                                                         :expand=>true, 
#                                                         :fill=>:both)

Tk.mainloop
