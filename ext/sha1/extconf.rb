require 'mkmf'

i = 0x01020304

case [i].pack('l')
  when [i].pack('V')
    $CFLAGS += " -DLITTLE_ENDIAN"
  when [i].pack('N')
    $CFLAGS += " -DBIG_ENDIAN"
  else
    p "Sorry, your machine has an unusual byte order which is not supported."
    exit!
end

create_makefile('sha1')
