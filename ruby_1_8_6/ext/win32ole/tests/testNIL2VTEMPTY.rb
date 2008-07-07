# This is test script to check that WIN32OLE should convert nil to VT_EMPTY in second try.
# [ruby-talk:137054]

require 'win32ole'
require 'test/unit'

class TestNIL2VT_EMPTY < Test::Unit::TestCase
  def setup
    fs = WIN32OLE.new('Scripting.FileSystemObject')
    @path = fs.GetFolder(".").path
  end
  def test_openSchema
    con = nil
    begin
      con = WIN32OLE.new('ADODB.Connection')
      con.connectionString = "Provider=MSDASQL;Extended Properties="
      con.connectionString +="\"DRIVER={Microsoft Text Driver (*.txt; *.csv)};DBQ=#{@path}\""
      con.open
    rescue
      con = nil
    end
    if con
      rs = con.openSchema(4, [nil,nil,"DUMMY", "TABLE"])
      assert(rs)
    end
  end
end

