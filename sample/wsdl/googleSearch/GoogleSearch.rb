# urn:GoogleSearch
class GoogleSearchResult
  @@schema_type = "GoogleSearchResult"
  @@schema_ns = "urn:GoogleSearch"

  def documentFiltering
    @documentFiltering
  end

  def documentFiltering=(value)
    @documentFiltering = value
  end

  def searchComments
    @searchComments
  end

  def searchComments=(value)
    @searchComments = value
  end

  def estimatedTotalResultsCount
    @estimatedTotalResultsCount
  end

  def estimatedTotalResultsCount=(value)
    @estimatedTotalResultsCount = value
  end

  def estimateIsExact
    @estimateIsExact
  end

  def estimateIsExact=(value)
    @estimateIsExact = value
  end

  def resultElements
    @resultElements
  end

  def resultElements=(value)
    @resultElements = value
  end

  def searchQuery
    @searchQuery
  end

  def searchQuery=(value)
    @searchQuery = value
  end

  def startIndex
    @startIndex
  end

  def startIndex=(value)
    @startIndex = value
  end

  def endIndex
    @endIndex
  end

  def endIndex=(value)
    @endIndex = value
  end

  def searchTips
    @searchTips
  end

  def searchTips=(value)
    @searchTips = value
  end

  def directoryCategories
    @directoryCategories
  end

  def directoryCategories=(value)
    @directoryCategories = value
  end

  def searchTime
    @searchTime
  end

  def searchTime=(value)
    @searchTime = value
  end

  def initialize(documentFiltering = nil,
      searchComments = nil,
      estimatedTotalResultsCount = nil,
      estimateIsExact = nil,
      resultElements = nil,
      searchQuery = nil,
      startIndex = nil,
      endIndex = nil,
      searchTips = nil,
      directoryCategories = nil,
      searchTime = nil)
    @documentFiltering = documentFiltering
    @searchComments = searchComments
    @estimatedTotalResultsCount = estimatedTotalResultsCount
    @estimateIsExact = estimateIsExact
    @resultElements = resultElements
    @searchQuery = searchQuery
    @startIndex = startIndex
    @endIndex = endIndex
    @searchTips = searchTips
    @directoryCategories = directoryCategories
    @searchTime = searchTime
  end
end

# urn:GoogleSearch
class ResultElement
  @@schema_type = "ResultElement"
  @@schema_ns = "urn:GoogleSearch"

  def summary
    @summary
  end

  def summary=(value)
    @summary = value
  end

  def URL
    @uRL
  end

  def URL=(value)
    @uRL = value
  end

  def snippet
    @snippet
  end

  def snippet=(value)
    @snippet = value
  end

  def title
    @title
  end

  def title=(value)
    @title = value
  end

  def cachedSize
    @cachedSize
  end

  def cachedSize=(value)
    @cachedSize = value
  end

  def relatedInformationPresent
    @relatedInformationPresent
  end

  def relatedInformationPresent=(value)
    @relatedInformationPresent = value
  end

  def hostName
    @hostName
  end

  def hostName=(value)
    @hostName = value
  end

  def directoryCategory
    @directoryCategory
  end

  def directoryCategory=(value)
    @directoryCategory = value
  end

  def directoryTitle
    @directoryTitle
  end

  def directoryTitle=(value)
    @directoryTitle = value
  end

  def initialize(summary = nil,
      uRL = nil,
      snippet = nil,
      title = nil,
      cachedSize = nil,
      relatedInformationPresent = nil,
      hostName = nil,
      directoryCategory = nil,
      directoryTitle = nil)
    @summary = summary
    @uRL = uRL
    @snippet = snippet
    @title = title
    @cachedSize = cachedSize
    @relatedInformationPresent = relatedInformationPresent
    @hostName = hostName
    @directoryCategory = directoryCategory
    @directoryTitle = directoryTitle
  end
end

# urn:GoogleSearch
class ResultElementArray < Array
  # Contents type should be dumped here...
  @@schema_type = "ResultElementArray"
  @@schema_ns = "urn:GoogleSearch"
end

# urn:GoogleSearch
class DirectoryCategoryArray < Array
  # Contents type should be dumped here...
  @@schema_type = "DirectoryCategoryArray"
  @@schema_ns = "urn:GoogleSearch"
end

# urn:GoogleSearch
class DirectoryCategory
  @@schema_type = "DirectoryCategory"
  @@schema_ns = "urn:GoogleSearch"

  def fullViewableName
    @fullViewableName
  end

  def fullViewableName=(value)
    @fullViewableName = value
  end

  def specialEncoding
    @specialEncoding
  end

  def specialEncoding=(value)
    @specialEncoding = value
  end

  def initialize(fullViewableName = nil,
      specialEncoding = nil)
    @fullViewableName = fullViewableName
    @specialEncoding = specialEncoding
  end
end

