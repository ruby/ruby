# socket example - client side
# usage: ruby clnt.rb [host] port

require "socket"

host=(if ARGV.length == 2; ARGV.shift; else "localhost"; end)
print("Trying ", host, " ...")
STDOUT.flush
s = TCPsocket.open(host, ARGV.shift)
print(" done\n")
print("addr: ", s.addr.join(":"), "\n")
print("peer: ", s.peeraddr.join(":"), "\n")
while gets()
  s.write($_)
  print(s.readline)
end
s.close
