# frozen_string_literal: false
require 'win32ole'

#application = WIN32OLE.new('Excel.Application.5')
application = WIN32OLE.new('Excel.Application')

application.visible = true
workbook = application.Workbooks.Add();
sheet = workbook.Worksheets(1);
sheetS = workbook.Worksheets
puts "The number of sheets is #{sheetS.count}"
puts "Now add 2 sheets after of `#{sheet.name}`"
sheetS.add({'count'=>2, 'after'=>sheet})
puts "The number of sheets is #{sheetS.count}"

print "Now quit Excel... Please enter."
gets

application.ActiveWorkbook.Close(0);
application.Quit();

