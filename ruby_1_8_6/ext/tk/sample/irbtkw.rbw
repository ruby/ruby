#!/usr/bin/env ruby
#
#  irbtkw.rb : IRB console with Ruby/Tk
#
#                                 by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
release = '2006/11/06'

require 'tk'
begin
  require 'tktextio'
rescue LoadError
  require File.join(File.dirname(File.expand_path(__FILE__)), 'tktextio.rb')
end

require 'irb'

# console setup
top = TkToplevel.new(:title=>'IRB console')
top.protocol(:WM_DELETE_WINDOW){ Tk.exit }

console = TkTextIO.new(top, :mode=>:console, 
                       :width=>80).pack(:side=>:left, 
                                        :expand=>true, :fill=>:both)
console.yscrollbar(TkScrollbar.new(top, :width=>10).pack(:before=>console, 
                                                         :side=>:right, 
                                                         :expand=>false, 
                                                         :fill=>:y))
irb_thread = nil
ev_loop = Thread.new{
  Tk.mainloop
  irb_thread.kill if irb_thread
}

# window position control
root = Tk.root

r_x = root.winfo_rootx
r_y = root.winfo_rooty
r_w = root.winfo_width

t_x = top.winfo_rootx
t_y = top.winfo_rooty
t_w = top.winfo_width

delta = 10

ratio = 0.8
s_w = (ratio * root.winfo_screenwidth).to_i

if r_x < t_x
  r_x, t_x = t_x, r_x
end
if t_x + t_w + r_w + delta < s_w
  r_x = t_x + t_w + delta
elsif t_w + r_w + delta < s_w
  r_x = s_w - r_w
  t_x = r_x - t_w
else
  r_x = s_w - r_w
  t_x = 0
end

root.geometry("+#{r_x}+#{r_y}")
top.geometry("+#{t_x}+#{t_y}")

root.raise
console.focus

# I/O setup
$stdin  = console
$stdout = console
$stderr = console

# dummy for rubyw.exe on Windows
def STDIN.tty?
  true
end

# IRB setup
IRB.init_config(nil)
IRB.conf[:USE_READLINE] = false
IRB.init_error
irb = IRB::Irb.new
IRB.conf[:MAIN_CONTEXT] = irb.context

class IRB::StdioInputMethod
  def gets
    prompt = "\n" << @prompt
    $stdin.instance_eval{
      flush
      @prompt = prompt
      _set_console_line
      @prompt = nil
      _see_pos
    }

    @line[@line_no += 1] = $stdin.gets
  end
end

# IRB start
$stdout.print("*** IRB console on Ruby/Tk (#{release})  ")
irb_thread = Thread.new{
  catch(:IRB_EXIT){
    loop {
      begin
        irb.eval_input
      rescue Exception
      end
    }
  }
}

console.bind('Control-c'){
  console.insert('end', "^C\n")
  irb_thread.raise RubyLex::TerminateLineInput
}

irb_thread.join

# exit
ev_thread.kill
Tk.exit
