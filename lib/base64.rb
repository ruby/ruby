def decode64(str)
  e = -1;
  c = ","
  string=''
  for line in str.split("\n")
    line.sub!(/=+$/, '')
    line.tr! 'A-Za-z0-9+/', "\000-\377"
    line.each_byte { |ch|
      n +=1
      e +=1
      if e==0
	c = ch << 2
      elsif e==1
	c |= ch >>4
	string += [c].pack('c')
	c = ch << 4
      elsif e == 2
	c |= ch >> 2
	string += [c].pack('c'); 
	c = ch << 6
      elsif e==3
	c |= ch
	string += [c].pack('c')
	e = -1
      end
    }
  end
  return string
end

def j2e(str)
  while str =~ /\033\$B([^\033]*)\033\(B/
    s = $1
    pre, post = $`, $'
    s.gsub!(/./) { |ch|
      (ch[0]|0x80).chr
    }
    str = pre + s + post
 end
#  str.gsub!(/\033\$B([^\033]*)\033\(B/) {
#    $1.gsub!(/./) { |ch|
#      (ch[0]|0x80).chr
#    }
#  }
  str
end

def decode_b(str)
  str.gsub!(/=\?ISO-2022-JP\?B\?([!->@-~]+)\?=/i) {
    decode64($1)
  }
  str.gsub!(/\n/, ' ') 
  str.gsub!(/\0/, '')
  j2e(str)
end
