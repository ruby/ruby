# frozen_string_literal: false
require 'win32ole'

application = WIN32OLE.new('Excel.Application')

application.visible = true
workbook = application.Workbooks.Add();
worksheet = workbook.Worksheets(1);

=begin
worksheet.Range("A1:D1").value = ["North","South","East","West"];
worksheet.Range("A2:B2").value = [5.2, 10];

worksheet.Range("C2").value = 8;
worksheet.Range("D2").value = 20;
=end

worksheet.Range("A1:B2").value = [["North","South"],
                                  [5.2, 10]];

vals = WIN32OLE_VARIANT.new([["East","West"],
                             [8, 20]],
                            WIN32OLE::VARIANT::VT_ARRAY)
worksheet.Range("C1:D2").value = vals

range = worksheet.Range("A1:D2");
range.Select
chart = workbook.Charts.Add;

workbook.saved = true;

print "Now quit Excel... Please enter."
gets

application.ActiveWorkbook.Close(0);
application.Quit();

