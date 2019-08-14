# frozen_string_literal: false
require 'win32ole'
url = 'http://www.ruby-lang.org/'
ie = WIN32OLE.new('InternetExplorer.Application')
ie.visible = true
ie.gohome
print "Now navigate Ruby home page... Please enter."
gets
ie.navigate(url)
print "Now quit Internet Explorer... Please enter."
gets
ie.Quit()
