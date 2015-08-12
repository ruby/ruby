require 'mkmf'
if try_cflags("-std=iso9899:1999")
  $CFLAGS += " " << "-std=iso9899:1999"
end
create_makefile('date_core')
