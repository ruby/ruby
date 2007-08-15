# This script works on Windows.

require 'dl'

User32 = DL.dlopen("user32")
Kernel32 = DL.dlopen("kernel32")

MB_OK = 0
MB_OKCANCEL = 1

message_box = User32['MessageBoxA', 'ILSSI']
r,rs = message_box.call(0, 'ok?', 'error', MB_OKCANCEL)

case r
when 1
  print("OK!\n")
when 2
  print("Cancel!\n")
end
