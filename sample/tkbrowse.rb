#!/usr/local/bin/ruby
#
# This script generates a directory browser, which lists the working
# directory and allows you to open files or subdirectories by
# double-clicking.

# Create a scrollbar on the right side of the main window and a listbox
# on the left side.

require "tkscrollbox"

list = TkScrollbox.new {
  relief 'raised'
  width 20
  height 20
  setgrid 'yes'
  pack
}

# The procedure below is invoked to open a browser on a given file;  if the
# file is a directory then another instance of this program is invoked; if
# the file is a regular file then the Mx editor is invoked to display
# the file.

def browse (dir, file)
  if dir != "."
    file="#{dir}/#{file}"
    if File.directory? file
      system "browse #{file} &"
    else
      if File.file? file
	if ENV['EDITOR']
	  system format("%s %s&", ENV['EDITOR'], file)
	else
	  sysmte "xedit #{file}&"
	end
      else
	STDERR.print "\"#{file}\" isn't a directory or regular file"
      end
    end
  end
end

# Fill the listbox with a list of all the files in the directory (run
# the "ls" command to get that information).

if ARGV.length>0 
  dir = ARGV[0]
else
  dir="."
end
list.insert 'end', *`ls #{dir}`.split

# Set up bindings for the browser.

list.focus
list.bind "Control-q", proc{exit}
list.bind "Control-c", proc{exit}
list.bind "Control-p", proc{
  print "selection <", TkSelection.get, ">\n"
}

list.bind "Double-Button-1", proc{
  for i in TkSelection.get.split
    print "clicked ", i, "\n"
    browse dir, i
  end
}
Tk.mainloop
