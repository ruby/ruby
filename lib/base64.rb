require "kconv"

def decode64(str)
  str.unpack("m")[0]
end

def decode_b(str)
  str.gsub!(/=\?ISO-2022-JP\?B\?([!->@-~]+)\?=/i) {
    decode64($1)
  }
  str = Kconv::toeuc(str)
  str.gsub!(/=\?SHIFT_JIS\?B\?([!->@-~]+)\?=/i) {
    decode64($1)
  }
  str = Kconv::toeuc(str)
  str.gsub!(/\n/, ' ') 
  str.gsub!(/\0/, '')
  str
end

def encode64(bin)
  [bin].pack("m")
end

def b64encode(bin, len = 60)
  encode64(bin).scan(/.{1,#{len}}/o) do
    print $&, "\n"
  end
end 
