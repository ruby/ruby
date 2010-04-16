class RAABaseServicePortType
  # SYNOPSIS
  #   getAllListings
  #
  # ARGS
  #   N/A
  #
  # RETURNS
  #   return		StringArray - {http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/}StringArray
  #
  # RAISES
  #   (undefined)
  #
  def getAllListings
    #raise NotImplementedError.new
    ["ruby", "soap4r"]
  end

  # SYNOPSIS
  #   getProductTree
  #
  # ARGS
  #   N/A
  #
  # RETURNS
  #   return		Map - {http://xml.apache.org/xml-soap}Map
  #
  # RAISES
  #   (undefined)
  #
  def getProductTree
    raise NotImplementedError.new
  end

  # SYNOPSIS
  #   getInfoFromCategory(category)
  #
  # ARGS
  #   category		Category - {http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/}Category
  #
  # RETURNS
  #   return		InfoArray - {http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/}InfoArray
  #
  # RAISES
  #   (undefined)
  #
  def getInfoFromCategory(category)
    raise NotImplementedError.new
  end

  # SYNOPSIS
  #   getModifiedInfoSince(timeInstant)
  #
  # ARGS
  #   timeInstant		 - {http://www.w3.org/2001/XMLSchema}dateTime
  #
  # RETURNS
  #   return		InfoArray - {http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/}InfoArray
  #
  # RAISES
  #   (undefined)
  #
  def getModifiedInfoSince(timeInstant)
    raise NotImplementedError.new
  end

  # SYNOPSIS
  #   getInfoFromName(productName)
  #
  # ARGS
  #   productName		 - {http://www.w3.org/2001/XMLSchema}string
  #
  # RETURNS
  #   return		Info - {http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/}Info
  #
  # RAISES
  #   (undefined)
  #
  def getInfoFromName(productName)
    raise NotImplementedError.new
  end

  # SYNOPSIS
  #   getInfoFromOwnerId(ownerId)
  #
  # ARGS
  #   ownerId		 - {http://www.w3.org/2001/XMLSchema}int
  #
  # RETURNS
  #   return		InfoArray - {http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/}InfoArray
  #
  # RAISES
  #   (undefined)
  #
  def getInfoFromOwnerId(ownerId)
    raise NotImplementedError.new
  end
end

