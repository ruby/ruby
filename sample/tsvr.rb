# socket example - server side using thread
# usage: ruby tsvr.rb

require "socket"

gs = TCPserver.open(0)
addr = gs.addr
addr.shift
printf("server is on %s\n", addr.join(":"))

while TRUE
  Thread.start(gs.accept) do |s|
    print(s, " is accepted\n")
    while s.gets
      s.write($_)
    end
    print(s, " is gone\n")
    s.close
  end
end
