gs = TCPserver.open(0)
printf("server port is on %d\n", gs.port)
socks = [gs]

while %TRUE
  nsock = select(socks);
  if nsock == nil; continue end
  for s in nsock[0]
    if s == gs
      socks.push(s.accept)
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
