#!/usr/local/bin/ruby

while gets()
  if /^begin\s*(\d*)\s*(\S*)/
    $mode, $file = $1, $2
    $sawbegin+=1
    break
  end
end

fail "missing begin" if !$sawbegin;
OUT = open($file, "w") if $file != "";

while gets()
  if /^end/
    $sawend+=1
    break
  end
  sub(/[a-z]+$/, ""); # handle stupid trailing lowercase letters
  continue if /[a-z]/
  continue if !(((($_[0] - 32) & 077) + 2) / 3 == $_.length / 4)
  OUT << $_.unpack("u");
end

fail "missing end" if ! $sawend;
File.chmod $mode.oct, $file;
exit 0;
