require 'dl'

crtdll = DL::dlopen("crtdll")
getch  = crtdll['_getch', 'L']
print(getch.call, "\n")
