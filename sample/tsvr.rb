# socket example - server side using thread
# usage: ruby tsvr.rb

require "socket"
require "thread"

gs = TCPserver.open(0)
addr = gs.addr
addr.shift
printf("server is on %d\n", addr.join(":"))

while TRUE
  ns = gs.accept
  print(ns, " is accepted\n")
  Thread.start do
    s =	ns			# save to thread-local variable
    while s.gets
      s.write($_)
    end
    print(s, " is gone\n")
    s.close
  end
end
