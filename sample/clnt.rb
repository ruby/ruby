host=(if $ARGV.length == 2; $ARGV.shift; else "localhost"; end)
print("Trying ", host, " ...")
$stdout.flush
s = TCPsocket.open(host, $ARGV.shift)
print(" done\n")
print("addr: ", s.addr.join(":"), "\n")
print("peer: ", s.peeraddr.join(":"), "\n")
while gets()
  s.write($_)
  print(s.gets)
end
s.close
