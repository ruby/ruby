module IICD
  # All methods in a single namespace?!
  InterfaceNS = 'http://www.iwebmethod.net'

  Methods = [
    ['SearchWord', 'query', 'partial'],
    ['GetItemById', 'id'],
    ['EnumWords'],
    ['FullTextSearch', 'query'],
  ]

  def IICD.add_method(drv)
    Methods.each do |method, *param|
      drv.add_method_with_soapaction(method, InterfaceNS + "/#{ method }", *param )
    end
  end
end
