require 'win32ole'
def oletypelib_name(pat)
  WIN32OLE_TYPE.typelibs.each do |lib|
    return lib if pat =~ lib
  end
end
module OLESERVER
  MS_EXCEL_TYPELIB = oletypelib_name(/^Microsoft Excel .* Object Library$/)
  MS_XML_TYPELIB = oletypelib_name(/^Microsoft XML/)
end
