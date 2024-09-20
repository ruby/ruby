# frozen_string_literal: false
require 'win32ole'

#   -4100 is the value for the Excel constant xl3DColumn.
ChartTypeVal = -4100;

#   Creates OLE object to Excel
excel = WIN32OLE.new("excel.application")

# Create and rotate the chart
excel.visible = true;
excel.Workbooks.Add();
excel.Range("a1").value = 3;
excel.Range("a2").value = 2;
excel.Range("a3").value = 1;
excel.Range("a1:a3").Select();
excelchart = excel.Charts.Add();
excelchart.type = ChartTypeVal;

i = 0
i.step(180, 10) do |rot|
    excelchart.rotation=rot;
    sleep 0.1
end
# Done, bye

print "Now quit Excel... Please enter."
gets

excel.ActiveWorkbook.Close(0);
excel.Quit();
