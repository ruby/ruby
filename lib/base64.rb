def decode64(str)
  string = ''
  for line in str.split("\n")
    line.delete!('^A-Za-z0-9+/')        # remove non-base64 chars
    line.tr!('A-Za-z0-9+/', ' -_')	# convert to uuencoded format
    len = ["#{32 + line.length * 3 / 4}"].pack("c")
					# compute length byte
    string += "#{len}#{line}".unpack("u") # uudecode and concatenate
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

def encode64(bin)
  encode = ""
  pad = 0
  [bin].pack("u").each do |uu|
    len = (2 + (uu[0] - 32)* 4) / 3
    encode << uu[1, len].tr('` -_', 'AA-Za-z0-9+/')
    pad += uu.length - 2 - len
  end
  encode + "=" * (pad % 3)
end

def b64encode(bin, len = 60)
  encode64(bin).scan(/.{1,#{len}}/o) do
    print $&, "\n"
  end
end 
