#!/usr/bin/env ruby
#
# This script implements the "ss" application.  "ss" implements
# a presentation slide-show based on HTML slides.
# 
require 'tk'
require 'tkextlib/tkHTML'

root  = TkRoot.new(:title=>'HTML File Viewer', :iconname=>'HV')
fswin = nil

html = nil
html_fs = nil

hotkey = {}

file = ARGV[0]


# These are images to use with the actual image specified in a
# "<img>" markup can't be found.
#
biggray = TkPhotoImage.new(:data=><<'EOD')
    R0lGODdhPAA+APAAALi4uAAAACwAAAAAPAA+AAACQISPqcvtD6OctNqLs968+w+G4kiW5omm
    6sq27gvH8kzX9o3n+s73/g8MCofEovGITCqXzKbzCY1Kp9Sq9YrNFgsAO///
EOD

smgray = TkPhotoImage.new(:data=><<'EOD')
    R0lGODdhOAAYAPAAALi4uAAAACwAAAAAOAAYAAACI4SPqcvtD6OctNqLs968+w+G4kiW5omm
    6sq27gvH8kzX9m0VADv/
EOD


#
# A font chooser routine.
#
# html[:fontcommand] = pick_font
pick_font = proc{|size, attrs|
  # puts "FontCmd: #{size} #{attrs}"
  [ ((attrs =~ /fixed/)? 'courier': 'charter'), 
    (12 * (1.2**(size.to_f - 4.0))).to_i, 
    ((attrs =~ /italic/)? 'italic': 'roman'), 
    ((attrs =~ /bold/)? 'bold': 'normal') ].join(' ')
} 

# This routine is called to pick fonts for the fullscreen view.
#
baseFontSize = 24
pick_font_fs = proc{|size, attrs|
  # puts "FontCmd: #{size} #{attrs}"
  [ ((attrs =~ /fixed/)? 'courier': 'charter'), 
    (baseFontSize * (1.2**(size.to_f - 4.0))).to_i, 
    ((attrs =~ /italic/)? 'italic': 'roman'), 
    ((attrs =~ /bold/)? 'bold': 'normal')  ].join(' ')
} 

#
#
hyper_cmd = proc{|*args|
  puts "HyperlinkCommand: #{args.inspect}"
}

# This routine is called to run an applet
#
applet_arg = TkVarAccess.new_hash('AppletArg')
run_applet = proc{|size, w, arglist|
  applet_arg.value = Hash[*simplelist(arglist)]

  return unless applet_arg.key?('src')

  src = html.remove(applet_arg['src'])

  applet_arg['window'] = w
  applet_arg['fontsize'] = size

  begin
    Tk.load_tclscript(src)
  rescue => e
    puts "Applet error: #{e.message}"
  end
}

#
#
form_cmd = proc{|n, cmd, *args|
}

#
#
images   = {}
old_imgs = {}
big_imgs = {}

#
#
move_big_image = proc{|b|
  return unless big_imgs.key?(b)
  b.copy(big_imgs[b])
  big_imgs[b].delete
  big_imgs.delete(b)
}

image_cmd = proc{|hs, *args|
  fn = args[0]

  if old_imgs.key?(fn)
    return (images[fn] = old_imgs.delete(fn))
  end

  begin
    img = TkPhotoImage.new(:file=>fn)
  rescue
    return ((hs)? smallgray: biggray)
  end

  if hs
    img2 = TkPhotoImage.new
    img2.copy(img, :subsample=>[2,2])
    img.delete
    img = img2
  end

  if img.width * img.height > 20000
    b = TkPhotoImage.new(:width=>img.width, :height=>img.height)
    big_imgs[b] = img
    img = b
    Tk.after_idle(proc{ move_big_image.call(b) })
  end

  images[fn] = img

  img
}


#
# This routine is called for every <SCRIPT> markup
#
script_cmd = proc{|*args|
  # puts "ScriptCmd: #{args.inspect}"
}

# This routine is called for every <APPLET> markup
#
applet_cmd = proc{|w, arglist| 
  # puts "AppletCmd: w=#{w} arglist=#{arglist}"
  #TkLabel.new(w, :text=>"The Applet #{w}", :bd=>2, :relief=>raised)
}

# This binding fires when there is a click on a hyperlink
#
href_binding = proc{|w, x, y|
  lst = w.href(x, y)
  unless lst.empty?
    process_url.call(lst)
  end
}

#
#
last_dir = Dir.pwd
sel_load = proc{
  filetypes = [
    ['Html Files', ['.html', '.htm']], 
    ['All Files', '*']
  ]

  f = Tk.getOpenFile(:initialdir=>last_dir, :filetypes=>filetypes)
  if f != ''
    load_file.call(f)
    last_dir = File.dirname(f)
  end
}

# Clear the screen.
#
clear_screen = proc{
  if html_fs && html_fs.exist?
    w = html_fs
  else
    w = html
  end
  w.clear
  old_imgs.clear
  big_imgs.clear
  hotkey.clear
  images.each{|k, v| old_imgs[k] = v }
  images.clear
}

# Read a file
#
read_file = proc{|name|
  begin
    fp = open(name, 'r')
    ret = fp.read(File.size(name))
  rescue
    ret = nil
    fp = nil
    Tk.messageBox(:icon=>'error', :message=>"fail to open '#{name}'", 
                  :type=>:ok)
  ensure
    fp.close if fp
  end
  ret
}

# Process the given URL
#
process_url = proc{|url|
  case url[0]
  when /^file:/
    load_file.call(url[0][5..-1])
  when /^exec:/
    Tk.ip_eval(url[0][5..-1].tr('\\', ' '))
  else
    load_file.call(url[0])
  end
}

# Load a file into the HTML widget
#
last_file = ''

load_file = proc{|name|
  return unless (doc = read_file.call(name))
  clear_screen.call
  last_file = name
  if html_fs && html_fs.exist?
    w = html_fs
  else
    w = html
  end
  w.configure(:base=>name)
  w.parse(doc)
  w.configure(:cursor=>'top_left_arrow')
  old_imgs.clear
}

# Refresh the current file.
#
refresh = proc{|*args|
  load_file.call(last_file) if last_file
}

# This routine is called whenever a "<meta>" markup is seen.
#
meta = proc{|w, tag, alist|
  v = Hash[*simplelist(alist)]

  if v.kye?('key') && v.key?('href')
    hotkey[v['key']] = w.resolve(v['href'])
  end

  if v.kye?('next')
    hotkey['Down'] =v['next']
  end

  if v.kye?('prev')
    hotkey['Up'] =v['prev']
  end

  if v.kye?('other')
    hotkey['o'] =v['other']
  end
}

# Go from full-screen mode back to window mode.
#
fullscreen_off = proc{
  fswin.destroy
  root.deiconify
  Tk.update
  root.raise
  html.clipwin.focus
  clear_screen.call
  old_imgs.clear
  refresh.call
}

# Go from window mode to full-screen mode.
#
fullscreen = proc{
  if fswin && fswin.exist?
    fswin.deiconify
    Tk.update
    fswin.raise
    return
  end

  width  =  root.winfo_screenwidth
  height =  root.winfo_screenheight
  fswin = TkToplevel.new(:overrideredirect=>true, 
                         :geometry=>"#{width}x#{height}+0+0")

  html_fs = Tk::HTML_Widget.new(fswin, :padx=>5, :pady=>9, 
                                :formcommand=>form_cmd, 
                                :imagecommand=>proc{image_cmd.call(0)}, 
                                :scriptcommand=>script_cmd, 
                                :appletcommand=>applet_cmd, 
                                :hyperlinkcommand=>hyper_cmd, 
                                :bg=>'white', :tablerelief=>:raised, 
                                :appletcommand=>proc{|*args|
                                  run_applet('big', *args)
                                }, 
                                :fontcommand=>pick_font_fs, 
                                :cursor=>:tcross) {
    pack(:fill=>:both, :expand=>true)
    token_handler('meta', proc{|*args| meta.call(self, *args)})
  }

  clear_screen.call
  old_imgs.clear
  refresh.call
  Tk.update
  html_fs.clipwin.focus
}

#
#
key_block = false

key_press = proc{|w, keysym|
  return if key_block
  key_block = true
  Tk.after(250, proc{key_block = false})

  if hotkey.key?(keysym)
    process_url.call(hotkey[keysym])
  end
  case keysym
  when 'Escape'
    if fswin && fswin.exist?
      fullscreen_off.call
    else
      fullscreen.call
    end
  end
}

Tk::HTML_Widget::ClippingWindow.bind('1', key_press, '%W Down')
Tk::HTML_Widget::ClippingWindow.bind('3', key_press, '%W Up')
Tk::HTML_Widget::ClippingWindow.bind('2', key_press, '%w Down')

Tk::HTML_Widget::ClippingWindow.bind('KeyPress', key_press, '%W %K')


############################################
#
# Build the half-size view of the page
#
menu_spec = [
  [['File', 0], 
    ['Open',        sel_load,   0], 
    ['Full Screen', fullscreen, 0], 
    ['Refresh',     refresh,    0], 
    '---',
    ['Exit', proc{exit}, 1]]
]

mbar = root.add_menubar(menu_spec)

html = Tk::HTML_Widget.new(:width=>512, :height=>384, 
                           :padx=>5, :pady=>9, 
                           :formcommand=>form_cmd, 
                           :imagecommand=>proc{|*args| 
                             image_cmd.call(1, *args)
                           }, 
                           :scriptcommand=>script_cmd, 
                           :appletcommand=>applet_cmd, 
                           :hyperlinkcommand=>hyper_cmd, 
                           :fontcommand=>pick_font, 
                           :appletcommand=>proc{|*args|
                             run_applet.call('small', *args)
                           }, 
                           :bg=>'white', :tablerelief=>:raised)

html.token_handler('meta', proc{|*args| meta.call(html, *args)})

vscr = html.yscrollbar(TkScrollbar.new)
hscr = html.xscrollbar(TkScrollbar.new)

Tk.grid(html, vscr, :sticky=>:news)
Tk.grid(hscr,       :sticky=>:ew)
Tk.root.grid_columnconfigure(0, :weight=>1)
Tk.root.grid_columnconfigure(1, :weight=>0)
Tk.root.grid_rowconfigure(0, :weight=>1)
Tk.root.grid_rowconfigure(1, :weight=>0)


############################################

html.clipwin.focus

# If an arguent was specified, read it into the HTML widget.
#
Tk.update
if file && file != ""
  load_file.call(file)
end

############################################

Tk.mainloop
