# This script works on Windows.

require 'dl/win32'

MB_OK = 0
MB_OKCANCEL = 1

message_box = Win32API.new("user32",'MessageBoxA', 'ISSI', 'I')
r = message_box.call(0, 'ok?', 'error', MB_OKCANCEL)

case r
when 1
  print("OK!\n")
when 2
  print("Cancel!\n")
else
  p r
end
