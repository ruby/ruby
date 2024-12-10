require 'mkmf'
if RUBY_ENGINE == "ruby" and have_library('iphlpapi', 'GetNetworkParams')
  create_makefile('win32/resolv')
else
  File.write('Makefile', "all clean install:\n\t@echo Done: $(@)\n")
end
