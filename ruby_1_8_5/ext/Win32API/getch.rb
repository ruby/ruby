require 'Win32API'

getch = Win32API.new("crtdll", "_getch", [], 'L')

puts getch.Call.chr
