#!/usr/local/bin/ruby

if ARGV[0] == "-c"
  out_stdout = 1;
  ARGV.shift
end

while gets()
  if /^begin\s*(\d*)\s*(\S*)/
    $mode, $file = $1, $2
    $sawbegin+=1
    break
  end
end

fail "missing begin" if ! $sawbegin;

if out_stdout
  out = STDOUT
else
  out = open($file, "w") if $file != "";
end

while gets()
  if /^end/
    $sawend+=1
    break
  end
  sub(/[a-z]+$/, ""); # handle stupid trailing lowercase letters
  next if /[a-z]/
  next if !(((($_[0] - 32) & 077) + 2) / 3 == $_.length / 4)
  out << $_.unpack("u");
end

fail "missing end" if !$sawend;
File.chmod $mode.oct, $file if ! out_stdout
exit 0;
