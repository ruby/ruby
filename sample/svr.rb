# socket example - server side
# usage: ruby svr.rb

require "socket"

gs = TCPserver.open(0)
addr = gs.addr
addr.shift
printf("server is on %s\n", addr.join(":"))
socks = [gs]

loop do
  nsock = select(socks);
  next if nsock == nil
  for s in nsock[0]
    if s == gs
      ns = s.accept
      socks.push(ns)
      print(s, " is accepted\n")
    else
      if s.eof?
	print(s, " is gone\n")
	s.close
	socks.delete(s)
      else
	if str = s.gets
	  s.write(str)
	end
      end
    end
  end
end
