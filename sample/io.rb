home = getenv("HOME")
print(home.sub("m", "&&"), home, "\n")
print(home.reverse, "\n")

if File.s("io.rb")
  print(File.s("io.rb"), ": io.rb\n")
end

$/="f\n"
for i in "abc\n\ndef\nghi\n"
  print("tt: ", i)
end

printf("%s:(%d)%s\n", $0, $ARGV.length, $ARGV[0])
passwd = open($ARGV[0], "r")
#printf("%s", do passwd.find using i; i =~ /\*/ end)

n = 1
for i in passwd #.grep(/^\*/)
  printf("%6d: %s", n, i)
  n = n + 1;
end

fp = open("|-", "r")

if fp == nil
  for i in 1..5
    print(i, "\n")
  end
else
  for line in fp
    print(line)
  end
end

def printUsage()
  if $USAGE
    apply($USAGE);
  end
end
