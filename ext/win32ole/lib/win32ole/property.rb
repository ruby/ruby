# frozen_string_literal: false

class WIN32OLE
end

# OLEProperty is a helper class of Property with arguments, used by
# `olegen.rb`-generated files.
class WIN32OLE::Property
  # :stopdoc:
  def initialize(obj, dispid, gettypes, settypes)
    @obj = obj
    @dispid = dispid
    @gettypes = gettypes
    @settypes = settypes
  end
  def [](*args)
    @obj._getproperty(@dispid, args, @gettypes)
  end
  def []=(*args)
    @obj._setproperty(@dispid, args, @settypes)
  end
  # :stopdoc:
end

module WIN32OLE::VariantType
  # Alias for `olegen.rb`-generated files, that should include
  # WIN32OLE::VARIANT.
  OLEProperty = WIN32OLE::Property
end
