require "tk"

TkButton.new {
  text 'hello'
  command proc{print "hello\n"}
  pack('fill'=>'x')
}
TkButton.new {
  text 'quit'
  command 'exit'
  pack('fill'=>'x')
}
Tk.mainloop
