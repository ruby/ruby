require 'rubyunit'
require 'win32ole'
puts "Now Test Win32OLE version #{WIN32OLE::VERSION}"
# RUNIT::CUI::TestRunner.quiet_mode = true
require "testWIN32OLE"
require "testOLETYPE"
require "testOLEPARAM"
require "testOLEMETHOD"
require "testOLEVARIABLE"
require "testVARIANT"
# require "testOLEEVENT"
