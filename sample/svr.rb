# socket example - server side
# usage: ruby svr.rb

gs = TCPserver.open(0)
addr = gs.addr
addr.shift
printf("server is on %d\n", addr.join(":"))
socks = [gs]

while TRUE
  nsock = select(socks);
  if nsock == nil; continue end
  for s in nsock[0]
    if s == gs
      ns = s.accept
      socks.push(ns)
      print(s, " is accepted\n")
    else
      if s.eof
	print(s, " is gone\n")
	s.close
	socks.delete(s)
      else
	if str = s.gets;
	  s.write(str)
	end
      end
    end
  end
end
