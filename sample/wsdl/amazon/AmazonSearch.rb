# http://soap.amazon.com
class ProductLineArray < Array
  # Contents type should be dumped here...
  @@schema_type = "ProductLineArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class ProductLine
  @@schema_type = "ProductLine"
  @@schema_ns = "http://soap.amazon.com"

  def Mode
    @mode
  end

  def Mode=(value)
    @mode = value
  end

  def ProductInfo
    @productInfo
  end

  def ProductInfo=(value)
    @productInfo = value
  end

  def initialize(mode = nil,
      productInfo = nil)
    @mode = mode
    @productInfo = productInfo
  end
end

# http://soap.amazon.com
class ProductInfo
  @@schema_type = "ProductInfo"
  @@schema_ns = "http://soap.amazon.com"

  def TotalResults
    @totalResults
  end

  def TotalResults=(value)
    @totalResults = value
  end

  def TotalPages
    @totalPages
  end

  def TotalPages=(value)
    @totalPages = value
  end

  def ListName
    @listName
  end

  def ListName=(value)
    @listName = value
  end

  def Details
    @details
  end

  def Details=(value)
    @details = value
  end

  def initialize(totalResults = nil,
      totalPages = nil,
      listName = nil,
      details = nil)
    @totalResults = totalResults
    @totalPages = totalPages
    @listName = listName
    @details = details
  end
end

# http://soap.amazon.com
class DetailsArray < Array
  # Contents type should be dumped here...
  @@schema_type = "DetailsArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class Details
  @@schema_type = "Details"
  @@schema_ns = "http://soap.amazon.com"

  def Url
    @url
  end

  def Url=(value)
    @url = value
  end

  def Asin
    @asin
  end

  def Asin=(value)
    @asin = value
  end

  def ProductName
    @productName
  end

  def ProductName=(value)
    @productName = value
  end

  def Catalog
    @catalog
  end

  def Catalog=(value)
    @catalog = value
  end

  def KeyPhrases
    @keyPhrases
  end

  def KeyPhrases=(value)
    @keyPhrases = value
  end

  def Artists
    @artists
  end

  def Artists=(value)
    @artists = value
  end

  def Authors
    @authors
  end

  def Authors=(value)
    @authors = value
  end

  def Mpn
    @mpn
  end

  def Mpn=(value)
    @mpn = value
  end

  def Starring
    @starring
  end

  def Starring=(value)
    @starring = value
  end

  def Directors
    @directors
  end

  def Directors=(value)
    @directors = value
  end

  def TheatricalReleaseDate
    @theatricalReleaseDate
  end

  def TheatricalReleaseDate=(value)
    @theatricalReleaseDate = value
  end

  def ReleaseDate
    @releaseDate
  end

  def ReleaseDate=(value)
    @releaseDate = value
  end

  def Manufacturer
    @manufacturer
  end

  def Manufacturer=(value)
    @manufacturer = value
  end

  def Distributor
    @distributor
  end

  def Distributor=(value)
    @distributor = value
  end

  def ImageUrlSmall
    @imageUrlSmall
  end

  def ImageUrlSmall=(value)
    @imageUrlSmall = value
  end

  def ImageUrlMedium
    @imageUrlMedium
  end

  def ImageUrlMedium=(value)
    @imageUrlMedium = value
  end

  def ImageUrlLarge
    @imageUrlLarge
  end

  def ImageUrlLarge=(value)
    @imageUrlLarge = value
  end

  def ListPrice
    @listPrice
  end

  def ListPrice=(value)
    @listPrice = value
  end

  def OurPrice
    @ourPrice
  end

  def OurPrice=(value)
    @ourPrice = value
  end

  def UsedPrice
    @usedPrice
  end

  def UsedPrice=(value)
    @usedPrice = value
  end

  def RefurbishedPrice
    @refurbishedPrice
  end

  def RefurbishedPrice=(value)
    @refurbishedPrice = value
  end

  def CollectiblePrice
    @collectiblePrice
  end

  def CollectiblePrice=(value)
    @collectiblePrice = value
  end

  def ThirdPartyNewPrice
    @thirdPartyNewPrice
  end

  def ThirdPartyNewPrice=(value)
    @thirdPartyNewPrice = value
  end

  def NumberOfOfferings
    @numberOfOfferings
  end

  def NumberOfOfferings=(value)
    @numberOfOfferings = value
  end

  def ThirdPartyNewCount
    @thirdPartyNewCount
  end

  def ThirdPartyNewCount=(value)
    @thirdPartyNewCount = value
  end

  def UsedCount
    @usedCount
  end

  def UsedCount=(value)
    @usedCount = value
  end

  def CollectibleCount
    @collectibleCount
  end

  def CollectibleCount=(value)
    @collectibleCount = value
  end

  def RefurbishedCount
    @refurbishedCount
  end

  def RefurbishedCount=(value)
    @refurbishedCount = value
  end

  def ThirdPartyProductInfo
    @thirdPartyProductInfo
  end

  def ThirdPartyProductInfo=(value)
    @thirdPartyProductInfo = value
  end

  def SalesRank
    @salesRank
  end

  def SalesRank=(value)
    @salesRank = value
  end

  def BrowseList
    @browseList
  end

  def BrowseList=(value)
    @browseList = value
  end

  def Media
    @media
  end

  def Media=(value)
    @media = value
  end

  def ReadingLevel
    @readingLevel
  end

  def ReadingLevel=(value)
    @readingLevel = value
  end

  def Publisher
    @publisher
  end

  def Publisher=(value)
    @publisher = value
  end

  def NumMedia
    @numMedia
  end

  def NumMedia=(value)
    @numMedia = value
  end

  def Isbn
    @isbn
  end

  def Isbn=(value)
    @isbn = value
  end

  def Features
    @features
  end

  def Features=(value)
    @features = value
  end

  def MpaaRating
    @mpaaRating
  end

  def MpaaRating=(value)
    @mpaaRating = value
  end

  def EsrbRating
    @esrbRating
  end

  def EsrbRating=(value)
    @esrbRating = value
  end

  def AgeGroup
    @ageGroup
  end

  def AgeGroup=(value)
    @ageGroup = value
  end

  def Availability
    @availability
  end

  def Availability=(value)
    @availability = value
  end

  def Upc
    @upc
  end

  def Upc=(value)
    @upc = value
  end

  def Tracks
    @tracks
  end

  def Tracks=(value)
    @tracks = value
  end

  def Accessories
    @accessories
  end

  def Accessories=(value)
    @accessories = value
  end

  def Platforms
    @platforms
  end

  def Platforms=(value)
    @platforms = value
  end

  def Encoding
    @encoding
  end

  def Encoding=(value)
    @encoding = value
  end

  def Reviews
    @reviews
  end

  def Reviews=(value)
    @reviews = value
  end

  def SimilarProducts
    @similarProducts
  end

  def SimilarProducts=(value)
    @similarProducts = value
  end

  def Lists
    @lists
  end

  def Lists=(value)
    @lists = value
  end

  def Status
    @status
  end

  def Status=(value)
    @status = value
  end

  def initialize(url = nil,
      asin = nil,
      productName = nil,
      catalog = nil,
      keyPhrases = nil,
      artists = nil,
      authors = nil,
      mpn = nil,
      starring = nil,
      directors = nil,
      theatricalReleaseDate = nil,
      releaseDate = nil,
      manufacturer = nil,
      distributor = nil,
      imageUrlSmall = nil,
      imageUrlMedium = nil,
      imageUrlLarge = nil,
      listPrice = nil,
      ourPrice = nil,
      usedPrice = nil,
      refurbishedPrice = nil,
      collectiblePrice = nil,
      thirdPartyNewPrice = nil,
      numberOfOfferings = nil,
      thirdPartyNewCount = nil,
      usedCount = nil,
      collectibleCount = nil,
      refurbishedCount = nil,
      thirdPartyProductInfo = nil,
      salesRank = nil,
      browseList = nil,
      media = nil,
      readingLevel = nil,
      publisher = nil,
      numMedia = nil,
      isbn = nil,
      features = nil,
      mpaaRating = nil,
      esrbRating = nil,
      ageGroup = nil,
      availability = nil,
      upc = nil,
      tracks = nil,
      accessories = nil,
      platforms = nil,
      encoding = nil,
      reviews = nil,
      similarProducts = nil,
      lists = nil,
      status = nil)
    @url = url
    @asin = asin
    @productName = productName
    @catalog = catalog
    @keyPhrases = keyPhrases
    @artists = artists
    @authors = authors
    @mpn = mpn
    @starring = starring
    @directors = directors
    @theatricalReleaseDate = theatricalReleaseDate
    @releaseDate = releaseDate
    @manufacturer = manufacturer
    @distributor = distributor
    @imageUrlSmall = imageUrlSmall
    @imageUrlMedium = imageUrlMedium
    @imageUrlLarge = imageUrlLarge
    @listPrice = listPrice
    @ourPrice = ourPrice
    @usedPrice = usedPrice
    @refurbishedPrice = refurbishedPrice
    @collectiblePrice = collectiblePrice
    @thirdPartyNewPrice = thirdPartyNewPrice
    @numberOfOfferings = numberOfOfferings
    @thirdPartyNewCount = thirdPartyNewCount
    @usedCount = usedCount
    @collectibleCount = collectibleCount
    @refurbishedCount = refurbishedCount
    @thirdPartyProductInfo = thirdPartyProductInfo
    @salesRank = salesRank
    @browseList = browseList
    @media = media
    @readingLevel = readingLevel
    @publisher = publisher
    @numMedia = numMedia
    @isbn = isbn
    @features = features
    @mpaaRating = mpaaRating
    @esrbRating = esrbRating
    @ageGroup = ageGroup
    @availability = availability
    @upc = upc
    @tracks = tracks
    @accessories = accessories
    @platforms = platforms
    @encoding = encoding
    @reviews = reviews
    @similarProducts = similarProducts
    @lists = lists
    @status = status
  end
end

# http://soap.amazon.com
class KeyPhraseArray < Array
  # Contents type should be dumped here...
  @@schema_type = "KeyPhraseArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class KeyPhrase
  @@schema_type = "KeyPhrase"
  @@schema_ns = "http://soap.amazon.com"

  def KeyPhrase
    @keyPhrase
  end

  def KeyPhrase=(value)
    @keyPhrase = value
  end

  def Type
    @type
  end

  def Type=(value)
    @type = value
  end

  def initialize(keyPhrase = nil,
      type = nil)
    @keyPhrase = keyPhrase
    @type = type
  end
end

# http://soap.amazon.com
class ArtistArray < Array
  # Contents type should be dumped here...
  @@schema_type = "ArtistArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class AuthorArray < Array
  # Contents type should be dumped here...
  @@schema_type = "AuthorArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class StarringArray < Array
  # Contents type should be dumped here...
  @@schema_type = "StarringArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class DirectorArray < Array
  # Contents type should be dumped here...
  @@schema_type = "DirectorArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class BrowseNodeArray < Array
  # Contents type should be dumped here...
  @@schema_type = "BrowseNodeArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class BrowseNode
  @@schema_type = "BrowseNode"
  @@schema_ns = "http://soap.amazon.com"

  def BrowseId
    @browseId
  end

  def BrowseId=(value)
    @browseId = value
  end

  def BrowseName
    @browseName
  end

  def BrowseName=(value)
    @browseName = value
  end

  def initialize(browseId = nil,
      browseName = nil)
    @browseId = browseId
    @browseName = browseName
  end
end

# http://soap.amazon.com
class FeaturesArray < Array
  # Contents type should be dumped here...
  @@schema_type = "FeaturesArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class TrackArray < Array
  # Contents type should be dumped here...
  @@schema_type = "TrackArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class Track
  @@schema_type = "Track"
  @@schema_ns = "http://soap.amazon.com"

  def TrackName
    @trackName
  end

  def TrackName=(value)
    @trackName = value
  end

  def ByArtist
    @byArtist
  end

  def ByArtist=(value)
    @byArtist = value
  end

  def initialize(trackName = nil,
      byArtist = nil)
    @trackName = trackName
    @byArtist = byArtist
  end
end

# http://soap.amazon.com
class AccessoryArray < Array
  # Contents type should be dumped here...
  @@schema_type = "AccessoryArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class PlatformArray < Array
  # Contents type should be dumped here...
  @@schema_type = "PlatformArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class Reviews
  @@schema_type = "Reviews"
  @@schema_ns = "http://soap.amazon.com"

  def AvgCustomerRating
    @avgCustomerRating
  end

  def AvgCustomerRating=(value)
    @avgCustomerRating = value
  end

  def TotalCustomerReviews
    @totalCustomerReviews
  end

  def TotalCustomerReviews=(value)
    @totalCustomerReviews = value
  end

  def CustomerReviews
    @customerReviews
  end

  def CustomerReviews=(value)
    @customerReviews = value
  end

  def initialize(avgCustomerRating = nil,
      totalCustomerReviews = nil,
      customerReviews = nil)
    @avgCustomerRating = avgCustomerRating
    @totalCustomerReviews = totalCustomerReviews
    @customerReviews = customerReviews
  end
end

# http://soap.amazon.com
class CustomerReviewArray < Array
  # Contents type should be dumped here...
  @@schema_type = "CustomerReviewArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class CustomerReview
  @@schema_type = "CustomerReview"
  @@schema_ns = "http://soap.amazon.com"

  def Rating
    @rating
  end

  def Rating=(value)
    @rating = value
  end

  def Summary
    @summary
  end

  def Summary=(value)
    @summary = value
  end

  def Comment
    @comment
  end

  def Comment=(value)
    @comment = value
  end

  def initialize(rating = nil,
      summary = nil,
      comment = nil)
    @rating = rating
    @summary = summary
    @comment = comment
  end
end

# http://soap.amazon.com
class SimilarProductsArray < Array
  # Contents type should be dumped here...
  @@schema_type = "SimilarProductsArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class ListArray < Array
  # Contents type should be dumped here...
  @@schema_type = "ListArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class MarketplaceSearch
  @@schema_type = "MarketplaceSearch"
  @@schema_ns = "http://soap.amazon.com"

  def MarketplaceSearchDetails
    @marketplaceSearchDetails
  end

  def MarketplaceSearchDetails=(value)
    @marketplaceSearchDetails = value
  end

  def initialize(marketplaceSearchDetails = nil)
    @marketplaceSearchDetails = marketplaceSearchDetails
  end
end

# http://soap.amazon.com
class SellerProfile
  @@schema_type = "SellerProfile"
  @@schema_ns = "http://soap.amazon.com"

  def SellerProfileDetails
    @sellerProfileDetails
  end

  def SellerProfileDetails=(value)
    @sellerProfileDetails = value
  end

  def initialize(sellerProfileDetails = nil)
    @sellerProfileDetails = sellerProfileDetails
  end
end

# http://soap.amazon.com
class SellerSearch
  @@schema_type = "SellerSearch"
  @@schema_ns = "http://soap.amazon.com"

  def SellerSearchDetails
    @sellerSearchDetails
  end

  def SellerSearchDetails=(value)
    @sellerSearchDetails = value
  end

  def initialize(sellerSearchDetails = nil)
    @sellerSearchDetails = sellerSearchDetails
  end
end

# http://soap.amazon.com
class MarketplaceSearchDetails
  @@schema_type = "MarketplaceSearchDetails"
  @@schema_ns = "http://soap.amazon.com"

  def NumberOfOpenListings
    @numberOfOpenListings
  end

  def NumberOfOpenListings=(value)
    @numberOfOpenListings = value
  end

  def ListingProductInfo
    @listingProductInfo
  end

  def ListingProductInfo=(value)
    @listingProductInfo = value
  end

  def initialize(numberOfOpenListings = nil,
      listingProductInfo = nil)
    @numberOfOpenListings = numberOfOpenListings
    @listingProductInfo = listingProductInfo
  end
end

# http://soap.amazon.com
class MarketplaceSearchDetailsArray < Array
  # Contents type should be dumped here...
  @@schema_type = "MarketplaceSearchDetailsArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class SellerProfileDetails
  @@schema_type = "SellerProfileDetails"
  @@schema_ns = "http://soap.amazon.com"

  def SellerNickname
    @sellerNickname
  end

  def SellerNickname=(value)
    @sellerNickname = value
  end

  def OverallFeedbackRating
    @overallFeedbackRating
  end

  def OverallFeedbackRating=(value)
    @overallFeedbackRating = value
  end

  def NumberOfFeedback
    @numberOfFeedback
  end

  def NumberOfFeedback=(value)
    @numberOfFeedback = value
  end

  def NumberOfCanceledBids
    @numberOfCanceledBids
  end

  def NumberOfCanceledBids=(value)
    @numberOfCanceledBids = value
  end

  def NumberOfCanceledAuctions
    @numberOfCanceledAuctions
  end

  def NumberOfCanceledAuctions=(value)
    @numberOfCanceledAuctions = value
  end

  def StoreId
    @storeId
  end

  def StoreId=(value)
    @storeId = value
  end

  def StoreName
    @storeName
  end

  def StoreName=(value)
    @storeName = value
  end

  def SellerFeedback
    @sellerFeedback
  end

  def SellerFeedback=(value)
    @sellerFeedback = value
  end

  def initialize(sellerNickname = nil,
      overallFeedbackRating = nil,
      numberOfFeedback = nil,
      numberOfCanceledBids = nil,
      numberOfCanceledAuctions = nil,
      storeId = nil,
      storeName = nil,
      sellerFeedback = nil)
    @sellerNickname = sellerNickname
    @overallFeedbackRating = overallFeedbackRating
    @numberOfFeedback = numberOfFeedback
    @numberOfCanceledBids = numberOfCanceledBids
    @numberOfCanceledAuctions = numberOfCanceledAuctions
    @storeId = storeId
    @storeName = storeName
    @sellerFeedback = sellerFeedback
  end
end

# http://soap.amazon.com
class SellerProfileDetailsArray < Array
  # Contents type should be dumped here...
  @@schema_type = "SellerProfileDetailsArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class SellerSearchDetails
  @@schema_type = "SellerSearchDetails"
  @@schema_ns = "http://soap.amazon.com"

  def SellerNickname
    @sellerNickname
  end

  def SellerNickname=(value)
    @sellerNickname = value
  end

  def StoreId
    @storeId
  end

  def StoreId=(value)
    @storeId = value
  end

  def StoreName
    @storeName
  end

  def StoreName=(value)
    @storeName = value
  end

  def NumberOfOpenListings
    @numberOfOpenListings
  end

  def NumberOfOpenListings=(value)
    @numberOfOpenListings = value
  end

  def ListingProductInfo
    @listingProductInfo
  end

  def ListingProductInfo=(value)
    @listingProductInfo = value
  end

  def initialize(sellerNickname = nil,
      storeId = nil,
      storeName = nil,
      numberOfOpenListings = nil,
      listingProductInfo = nil)
    @sellerNickname = sellerNickname
    @storeId = storeId
    @storeName = storeName
    @numberOfOpenListings = numberOfOpenListings
    @listingProductInfo = listingProductInfo
  end
end

# http://soap.amazon.com
class SellerSearchDetailsArray < Array
  # Contents type should be dumped here...
  @@schema_type = "SellerSearchDetailsArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class ListingProductInfo
  @@schema_type = "ListingProductInfo"
  @@schema_ns = "http://soap.amazon.com"

  def ListingProductDetails
    @listingProductDetails
  end

  def ListingProductDetails=(value)
    @listingProductDetails = value
  end

  def initialize(listingProductDetails = nil)
    @listingProductDetails = listingProductDetails
  end
end

# http://soap.amazon.com
class ListingProductDetailsArray < Array
  # Contents type should be dumped here...
  @@schema_type = "ListingProductDetailsArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class ListingProductDetails
  @@schema_type = "ListingProductDetails"
  @@schema_ns = "http://soap.amazon.com"

  def ExchangeId
    @exchangeId
  end

  def ExchangeId=(value)
    @exchangeId = value
  end

  def ListingId
    @listingId
  end

  def ListingId=(value)
    @listingId = value
  end

  def ExchangeTitle
    @exchangeTitle
  end

  def ExchangeTitle=(value)
    @exchangeTitle = value
  end

  def ExchangePrice
    @exchangePrice
  end

  def ExchangePrice=(value)
    @exchangePrice = value
  end

  def ExchangeAsin
    @exchangeAsin
  end

  def ExchangeAsin=(value)
    @exchangeAsin = value
  end

  def ExchangeEndDate
    @exchangeEndDate
  end

  def ExchangeEndDate=(value)
    @exchangeEndDate = value
  end

  def ExchangeTinyImage
    @exchangeTinyImage
  end

  def ExchangeTinyImage=(value)
    @exchangeTinyImage = value
  end

  def ExchangeSellerId
    @exchangeSellerId
  end

  def ExchangeSellerId=(value)
    @exchangeSellerId = value
  end

  def ExchangeSellerNickname
    @exchangeSellerNickname
  end

  def ExchangeSellerNickname=(value)
    @exchangeSellerNickname = value
  end

  def ExchangeStartDate
    @exchangeStartDate
  end

  def ExchangeStartDate=(value)
    @exchangeStartDate = value
  end

  def ExchangeStatus
    @exchangeStatus
  end

  def ExchangeStatus=(value)
    @exchangeStatus = value
  end

  def ExchangeQuantity
    @exchangeQuantity
  end

  def ExchangeQuantity=(value)
    @exchangeQuantity = value
  end

  def ExchangeQuantityAllocated
    @exchangeQuantityAllocated
  end

  def ExchangeQuantityAllocated=(value)
    @exchangeQuantityAllocated = value
  end

  def ExchangeFeaturedCategory
    @exchangeFeaturedCategory
  end

  def ExchangeFeaturedCategory=(value)
    @exchangeFeaturedCategory = value
  end

  def ExchangeCondition
    @exchangeCondition
  end

  def ExchangeCondition=(value)
    @exchangeCondition = value
  end

  def ExchangeConditionType
    @exchangeConditionType
  end

  def ExchangeConditionType=(value)
    @exchangeConditionType = value
  end

  def ExchangeAvailability
    @exchangeAvailability
  end

  def ExchangeAvailability=(value)
    @exchangeAvailability = value
  end

  def ExchangeOfferingType
    @exchangeOfferingType
  end

  def ExchangeOfferingType=(value)
    @exchangeOfferingType = value
  end

  def ExchangeSellerState
    @exchangeSellerState
  end

  def ExchangeSellerState=(value)
    @exchangeSellerState = value
  end

  def ExchangeSellerCountry
    @exchangeSellerCountry
  end

  def ExchangeSellerCountry=(value)
    @exchangeSellerCountry = value
  end

  def ExchangeSellerRating
    @exchangeSellerRating
  end

  def ExchangeSellerRating=(value)
    @exchangeSellerRating = value
  end

  def initialize(exchangeId = nil,
      listingId = nil,
      exchangeTitle = nil,
      exchangePrice = nil,
      exchangeAsin = nil,
      exchangeEndDate = nil,
      exchangeTinyImage = nil,
      exchangeSellerId = nil,
      exchangeSellerNickname = nil,
      exchangeStartDate = nil,
      exchangeStatus = nil,
      exchangeQuantity = nil,
      exchangeQuantityAllocated = nil,
      exchangeFeaturedCategory = nil,
      exchangeCondition = nil,
      exchangeConditionType = nil,
      exchangeAvailability = nil,
      exchangeOfferingType = nil,
      exchangeSellerState = nil,
      exchangeSellerCountry = nil,
      exchangeSellerRating = nil)
    @exchangeId = exchangeId
    @listingId = listingId
    @exchangeTitle = exchangeTitle
    @exchangePrice = exchangePrice
    @exchangeAsin = exchangeAsin
    @exchangeEndDate = exchangeEndDate
    @exchangeTinyImage = exchangeTinyImage
    @exchangeSellerId = exchangeSellerId
    @exchangeSellerNickname = exchangeSellerNickname
    @exchangeStartDate = exchangeStartDate
    @exchangeStatus = exchangeStatus
    @exchangeQuantity = exchangeQuantity
    @exchangeQuantityAllocated = exchangeQuantityAllocated
    @exchangeFeaturedCategory = exchangeFeaturedCategory
    @exchangeCondition = exchangeCondition
    @exchangeConditionType = exchangeConditionType
    @exchangeAvailability = exchangeAvailability
    @exchangeOfferingType = exchangeOfferingType
    @exchangeSellerState = exchangeSellerState
    @exchangeSellerCountry = exchangeSellerCountry
    @exchangeSellerRating = exchangeSellerRating
  end
end

# http://soap.amazon.com
class SellerFeedback
  @@schema_type = "SellerFeedback"
  @@schema_ns = "http://soap.amazon.com"

  def Feedback
    @feedback
  end

  def Feedback=(value)
    @feedback = value
  end

  def initialize(feedback = nil)
    @feedback = feedback
  end
end

# http://soap.amazon.com
class FeedbackArray < Array
  # Contents type should be dumped here...
  @@schema_type = "FeedbackArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class Feedback
  @@schema_type = "Feedback"
  @@schema_ns = "http://soap.amazon.com"

  def FeedbackRating
    @feedbackRating
  end

  def FeedbackRating=(value)
    @feedbackRating = value
  end

  def FeedbackComments
    @feedbackComments
  end

  def FeedbackComments=(value)
    @feedbackComments = value
  end

  def FeedbackDate
    @feedbackDate
  end

  def FeedbackDate=(value)
    @feedbackDate = value
  end

  def FeedbackRater
    @feedbackRater
  end

  def FeedbackRater=(value)
    @feedbackRater = value
  end

  def initialize(feedbackRating = nil,
      feedbackComments = nil,
      feedbackDate = nil,
      feedbackRater = nil)
    @feedbackRating = feedbackRating
    @feedbackComments = feedbackComments
    @feedbackDate = feedbackDate
    @feedbackRater = feedbackRater
  end
end

# http://soap.amazon.com
class ThirdPartyProductInfo
  @@schema_type = "ThirdPartyProductInfo"
  @@schema_ns = "http://soap.amazon.com"

  def ThirdPartyProductDetails
    @thirdPartyProductDetails
  end

  def ThirdPartyProductDetails=(value)
    @thirdPartyProductDetails = value
  end

  def initialize(thirdPartyProductDetails = nil)
    @thirdPartyProductDetails = thirdPartyProductDetails
  end
end

# http://soap.amazon.com
class ThirdPartyProductDetailsArray < Array
  # Contents type should be dumped here...
  @@schema_type = "ThirdPartyProductDetailsArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class ThirdPartyProductDetails
  @@schema_type = "ThirdPartyProductDetails"
  @@schema_ns = "http://soap.amazon.com"

  def OfferingType
    @offeringType
  end

  def OfferingType=(value)
    @offeringType = value
  end

  def SellerId
    @sellerId
  end

  def SellerId=(value)
    @sellerId = value
  end

  def SellerNickname
    @sellerNickname
  end

  def SellerNickname=(value)
    @sellerNickname = value
  end

  def ExchangeId
    @exchangeId
  end

  def ExchangeId=(value)
    @exchangeId = value
  end

  def OfferingPrice
    @offeringPrice
  end

  def OfferingPrice=(value)
    @offeringPrice = value
  end

  def Condition
    @condition
  end

  def Condition=(value)
    @condition = value
  end

  def ConditionType
    @conditionType
  end

  def ConditionType=(value)
    @conditionType = value
  end

  def ExchangeAvailability
    @exchangeAvailability
  end

  def ExchangeAvailability=(value)
    @exchangeAvailability = value
  end

  def SellerCountry
    @sellerCountry
  end

  def SellerCountry=(value)
    @sellerCountry = value
  end

  def SellerState
    @sellerState
  end

  def SellerState=(value)
    @sellerState = value
  end

  def ShipComments
    @shipComments
  end

  def ShipComments=(value)
    @shipComments = value
  end

  def SellerRating
    @sellerRating
  end

  def SellerRating=(value)
    @sellerRating = value
  end

  def initialize(offeringType = nil,
      sellerId = nil,
      sellerNickname = nil,
      exchangeId = nil,
      offeringPrice = nil,
      condition = nil,
      conditionType = nil,
      exchangeAvailability = nil,
      sellerCountry = nil,
      sellerState = nil,
      shipComments = nil,
      sellerRating = nil)
    @offeringType = offeringType
    @sellerId = sellerId
    @sellerNickname = sellerNickname
    @exchangeId = exchangeId
    @offeringPrice = offeringPrice
    @condition = condition
    @conditionType = conditionType
    @exchangeAvailability = exchangeAvailability
    @sellerCountry = sellerCountry
    @sellerState = sellerState
    @shipComments = shipComments
    @sellerRating = sellerRating
  end
end

# http://soap.amazon.com
class KeywordRequest
  @@schema_type = "KeywordRequest"
  @@schema_ns = "http://soap.amazon.com"

  def keyword
    @keyword
  end

  def keyword=(value)
    @keyword = value
  end

  def page
    @page
  end

  def page=(value)
    @page = value
  end

  def mode
    @mode
  end

  def mode=(value)
    @mode = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def sort
    @sort
  end

  def sort=(value)
    @sort = value
  end

  def variations
    @variations
  end

  def variations=(value)
    @variations = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(keyword = nil,
      page = nil,
      mode = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      sort = nil,
      variations = nil,
      locale = nil)
    @keyword = keyword
    @page = page
    @mode = mode
    @tag = tag
    @type = type
    @devtag = devtag
    @sort = sort
    @variations = variations
    @locale = locale
  end
end

# http://soap.amazon.com
class PowerRequest
  @@schema_type = "PowerRequest"
  @@schema_ns = "http://soap.amazon.com"

  def power
    @power
  end

  def power=(value)
    @power = value
  end

  def page
    @page
  end

  def page=(value)
    @page = value
  end

  def mode
    @mode
  end

  def mode=(value)
    @mode = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def sort
    @sort
  end

  def sort=(value)
    @sort = value
  end

  def variations
    @variations
  end

  def variations=(value)
    @variations = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(power = nil,
      page = nil,
      mode = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      sort = nil,
      variations = nil,
      locale = nil)
    @power = power
    @page = page
    @mode = mode
    @tag = tag
    @type = type
    @devtag = devtag
    @sort = sort
    @variations = variations
    @locale = locale
  end
end

# http://soap.amazon.com
class BrowseNodeRequest
  @@schema_type = "BrowseNodeRequest"
  @@schema_ns = "http://soap.amazon.com"

  def browse_node
    @browse_node
  end

  def browse_node=(value)
    @browse_node = value
  end

  def page
    @page
  end

  def page=(value)
    @page = value
  end

  def mode
    @mode
  end

  def mode=(value)
    @mode = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def sort
    @sort
  end

  def sort=(value)
    @sort = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(browse_node = nil,
      page = nil,
      mode = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      sort = nil,
      locale = nil)
    @browse_node = browse_node
    @page = page
    @mode = mode
    @tag = tag
    @type = type
    @devtag = devtag
    @sort = sort
    @locale = locale
  end
end

# http://soap.amazon.com
class AsinRequest
  @@schema_type = "AsinRequest"
  @@schema_ns = "http://soap.amazon.com"

  def asin
    @asin
  end

  def asin=(value)
    @asin = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def offer
    @offer
  end

  def offer=(value)
    @offer = value
  end

  def offerpage
    @offerpage
  end

  def offerpage=(value)
    @offerpage = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(asin = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      offer = nil,
      offerpage = nil,
      locale = nil)
    @asin = asin
    @tag = tag
    @type = type
    @devtag = devtag
    @offer = offer
    @offerpage = offerpage
    @locale = locale
  end
end

# http://soap.amazon.com
class BlendedRequest
  @@schema_type = "BlendedRequest"
  @@schema_ns = "http://soap.amazon.com"

  def blended
    @blended
  end

  def blended=(value)
    @blended = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(blended = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      locale = nil)
    @blended = blended
    @tag = tag
    @type = type
    @devtag = devtag
    @locale = locale
  end
end

# http://soap.amazon.com
class UpcRequest
  @@schema_type = "UpcRequest"
  @@schema_ns = "http://soap.amazon.com"

  def upc
    @upc
  end

  def upc=(value)
    @upc = value
  end

  def mode
    @mode
  end

  def mode=(value)
    @mode = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def sort
    @sort
  end

  def sort=(value)
    @sort = value
  end

  def variations
    @variations
  end

  def variations=(value)
    @variations = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(upc = nil,
      mode = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      sort = nil,
      variations = nil,
      locale = nil)
    @upc = upc
    @mode = mode
    @tag = tag
    @type = type
    @devtag = devtag
    @sort = sort
    @variations = variations
    @locale = locale
  end
end

# http://soap.amazon.com
class ArtistRequest
  @@schema_type = "ArtistRequest"
  @@schema_ns = "http://soap.amazon.com"

  def artist
    @artist
  end

  def artist=(value)
    @artist = value
  end

  def page
    @page
  end

  def page=(value)
    @page = value
  end

  def mode
    @mode
  end

  def mode=(value)
    @mode = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def sort
    @sort
  end

  def sort=(value)
    @sort = value
  end

  def variations
    @variations
  end

  def variations=(value)
    @variations = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(artist = nil,
      page = nil,
      mode = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      sort = nil,
      variations = nil,
      locale = nil)
    @artist = artist
    @page = page
    @mode = mode
    @tag = tag
    @type = type
    @devtag = devtag
    @sort = sort
    @variations = variations
    @locale = locale
  end
end

# http://soap.amazon.com
class AuthorRequest
  @@schema_type = "AuthorRequest"
  @@schema_ns = "http://soap.amazon.com"

  def author
    @author
  end

  def author=(value)
    @author = value
  end

  def page
    @page
  end

  def page=(value)
    @page = value
  end

  def mode
    @mode
  end

  def mode=(value)
    @mode = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def sort
    @sort
  end

  def sort=(value)
    @sort = value
  end

  def variations
    @variations
  end

  def variations=(value)
    @variations = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(author = nil,
      page = nil,
      mode = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      sort = nil,
      variations = nil,
      locale = nil)
    @author = author
    @page = page
    @mode = mode
    @tag = tag
    @type = type
    @devtag = devtag
    @sort = sort
    @variations = variations
    @locale = locale
  end
end

# http://soap.amazon.com
class ActorRequest
  @@schema_type = "ActorRequest"
  @@schema_ns = "http://soap.amazon.com"

  def actor
    @actor
  end

  def actor=(value)
    @actor = value
  end

  def page
    @page
  end

  def page=(value)
    @page = value
  end

  def mode
    @mode
  end

  def mode=(value)
    @mode = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def sort
    @sort
  end

  def sort=(value)
    @sort = value
  end

  def variations
    @variations
  end

  def variations=(value)
    @variations = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(actor = nil,
      page = nil,
      mode = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      sort = nil,
      variations = nil,
      locale = nil)
    @actor = actor
    @page = page
    @mode = mode
    @tag = tag
    @type = type
    @devtag = devtag
    @sort = sort
    @variations = variations
    @locale = locale
  end
end

# http://soap.amazon.com
class DirectorRequest
  @@schema_type = "DirectorRequest"
  @@schema_ns = "http://soap.amazon.com"

  def director
    @director
  end

  def director=(value)
    @director = value
  end

  def page
    @page
  end

  def page=(value)
    @page = value
  end

  def mode
    @mode
  end

  def mode=(value)
    @mode = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def sort
    @sort
  end

  def sort=(value)
    @sort = value
  end

  def variations
    @variations
  end

  def variations=(value)
    @variations = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(director = nil,
      page = nil,
      mode = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      sort = nil,
      variations = nil,
      locale = nil)
    @director = director
    @page = page
    @mode = mode
    @tag = tag
    @type = type
    @devtag = devtag
    @sort = sort
    @variations = variations
    @locale = locale
  end
end

# http://soap.amazon.com
class ExchangeRequest
  @@schema_type = "ExchangeRequest"
  @@schema_ns = "http://soap.amazon.com"

  def exchange_id
    @exchange_id
  end

  def exchange_id=(value)
    @exchange_id = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(exchange_id = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      locale = nil)
    @exchange_id = exchange_id
    @tag = tag
    @type = type
    @devtag = devtag
    @locale = locale
  end
end

# http://soap.amazon.com
class ManufacturerRequest
  @@schema_type = "ManufacturerRequest"
  @@schema_ns = "http://soap.amazon.com"

  def manufacturer
    @manufacturer
  end

  def manufacturer=(value)
    @manufacturer = value
  end

  def page
    @page
  end

  def page=(value)
    @page = value
  end

  def mode
    @mode
  end

  def mode=(value)
    @mode = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def sort
    @sort
  end

  def sort=(value)
    @sort = value
  end

  def variations
    @variations
  end

  def variations=(value)
    @variations = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(manufacturer = nil,
      page = nil,
      mode = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      sort = nil,
      variations = nil,
      locale = nil)
    @manufacturer = manufacturer
    @page = page
    @mode = mode
    @tag = tag
    @type = type
    @devtag = devtag
    @sort = sort
    @variations = variations
    @locale = locale
  end
end

# http://soap.amazon.com
class ListManiaRequest
  @@schema_type = "ListManiaRequest"
  @@schema_ns = "http://soap.amazon.com"

  def lm_id
    @lm_id
  end

  def lm_id=(value)
    @lm_id = value
  end

  def page
    @page
  end

  def page=(value)
    @page = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(lm_id = nil,
      page = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      locale = nil)
    @lm_id = lm_id
    @page = page
    @tag = tag
    @type = type
    @devtag = devtag
    @locale = locale
  end
end

# http://soap.amazon.com
class WishlistRequest
  @@schema_type = "WishlistRequest"
  @@schema_ns = "http://soap.amazon.com"

  def wishlist_id
    @wishlist_id
  end

  def wishlist_id=(value)
    @wishlist_id = value
  end

  def page
    @page
  end

  def page=(value)
    @page = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(wishlist_id = nil,
      page = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      locale = nil)
    @wishlist_id = wishlist_id
    @page = page
    @tag = tag
    @type = type
    @devtag = devtag
    @locale = locale
  end
end

# http://soap.amazon.com
class MarketplaceRequest
  @@schema_type = "MarketplaceRequest"
  @@schema_ns = "http://soap.amazon.com"

  def marketplace_search
    @marketplace_search
  end

  def marketplace_search=(value)
    @marketplace_search = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def page
    @page
  end

  def page=(value)
    @page = value
  end

  def keyword
    @keyword
  end

  def keyword=(value)
    @keyword = value
  end

  def keyword_search
    @keyword_search
  end

  def keyword_search=(value)
    @keyword_search = value
  end

  def browse_id
    @browse_id
  end

  def browse_id=(value)
    @browse_id = value
  end

  def zipcode
    @zipcode
  end

  def zipcode=(value)
    @zipcode = value
  end

  def area_id
    @area_id
  end

  def area_id=(value)
    @area_id = value
  end

  def geo
    @geo
  end

  def geo=(value)
    @geo = value
  end

  def sort
    @sort
  end

  def sort=(value)
    @sort = value
  end

  def listing_id
    @listing_id
  end

  def listing_id=(value)
    @listing_id = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def index
    @index
  end

  def index=(value)
    @index = value
  end

  def initialize(marketplace_search = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      page = nil,
      keyword = nil,
      keyword_search = nil,
      browse_id = nil,
      zipcode = nil,
      area_id = nil,
      geo = nil,
      sort = nil,
      listing_id = nil,
      locale = nil,
      index = nil)
    @marketplace_search = marketplace_search
    @tag = tag
    @type = type
    @devtag = devtag
    @page = page
    @keyword = keyword
    @keyword_search = keyword_search
    @browse_id = browse_id
    @zipcode = zipcode
    @area_id = area_id
    @geo = geo
    @sort = sort
    @listing_id = listing_id
    @locale = locale
    @index = index
  end
end

# http://soap.amazon.com
class SellerProfileRequest
  @@schema_type = "SellerProfileRequest"
  @@schema_ns = "http://soap.amazon.com"

  def seller_id
    @seller_id
  end

  def seller_id=(value)
    @seller_id = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def page
    @page
  end

  def page=(value)
    @page = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(seller_id = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      page = nil,
      locale = nil)
    @seller_id = seller_id
    @tag = tag
    @type = type
    @devtag = devtag
    @page = page
    @locale = locale
  end
end

# http://soap.amazon.com
class SellerRequest
  @@schema_type = "SellerRequest"
  @@schema_ns = "http://soap.amazon.com"

  def seller_id
    @seller_id
  end

  def seller_id=(value)
    @seller_id = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def offerstatus
    @offerstatus
  end

  def offerstatus=(value)
    @offerstatus = value
  end

  def page
    @page
  end

  def page=(value)
    @page = value
  end

  def seller_browse_id
    @seller_browse_id
  end

  def seller_browse_id=(value)
    @seller_browse_id = value
  end

  def keyword
    @keyword
  end

  def keyword=(value)
    @keyword = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def index
    @index
  end

  def index=(value)
    @index = value
  end

  def initialize(seller_id = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      offerstatus = nil,
      page = nil,
      seller_browse_id = nil,
      keyword = nil,
      locale = nil,
      index = nil)
    @seller_id = seller_id
    @tag = tag
    @type = type
    @devtag = devtag
    @offerstatus = offerstatus
    @page = page
    @seller_browse_id = seller_browse_id
    @keyword = keyword
    @locale = locale
    @index = index
  end
end

# http://soap.amazon.com
class SimilarityRequest
  @@schema_type = "SimilarityRequest"
  @@schema_ns = "http://soap.amazon.com"

  def asin
    @asin
  end

  def asin=(value)
    @asin = value
  end

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def type
    @type
  end

  def type=(value)
    @type = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(asin = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      locale = nil)
    @asin = asin
    @tag = tag
    @type = type
    @devtag = devtag
    @locale = locale
  end
end

# http://soap.amazon.com
class ItemIdArray < Array
  # Contents type should be dumped here...
  @@schema_type = "ItemIdArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class ItemArray < Array
  # Contents type should be dumped here...
  @@schema_type = "ItemArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class Item
  @@schema_type = "Item"
  @@schema_ns = "http://soap.amazon.com"

  def ItemId
    @itemId
  end

  def ItemId=(value)
    @itemId = value
  end

  def ProductName
    @productName
  end

  def ProductName=(value)
    @productName = value
  end

  def Catalog
    @catalog
  end

  def Catalog=(value)
    @catalog = value
  end

  def Asin
    @asin
  end

  def Asin=(value)
    @asin = value
  end

  def ExchangeId
    @exchangeId
  end

  def ExchangeId=(value)
    @exchangeId = value
  end

  def Quantity
    @quantity
  end

  def Quantity=(value)
    @quantity = value
  end

  def ListPrice
    @listPrice
  end

  def ListPrice=(value)
    @listPrice = value
  end

  def OurPrice
    @ourPrice
  end

  def OurPrice=(value)
    @ourPrice = value
  end

  def initialize(itemId = nil,
      productName = nil,
      catalog = nil,
      asin = nil,
      exchangeId = nil,
      quantity = nil,
      listPrice = nil,
      ourPrice = nil)
    @itemId = itemId
    @productName = productName
    @catalog = catalog
    @asin = asin
    @exchangeId = exchangeId
    @quantity = quantity
    @listPrice = listPrice
    @ourPrice = ourPrice
  end
end

# http://soap.amazon.com
class ItemQuantityArray < Array
  # Contents type should be dumped here...
  @@schema_type = "ItemQuantityArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class ItemQuantity
  @@schema_type = "ItemQuantity"
  @@schema_ns = "http://soap.amazon.com"

  def ItemId
    @itemId
  end

  def ItemId=(value)
    @itemId = value
  end

  def Quantity
    @quantity
  end

  def Quantity=(value)
    @quantity = value
  end

  def initialize(itemId = nil,
      quantity = nil)
    @itemId = itemId
    @quantity = quantity
  end
end

# http://soap.amazon.com
class AddItemArray < Array
  # Contents type should be dumped here...
  @@schema_type = "AddItemArray"
  @@schema_ns = "http://soap.amazon.com"
end

# http://soap.amazon.com
class AddItem
  @@schema_type = "AddItem"
  @@schema_ns = "http://soap.amazon.com"

  def Asin
    @asin
  end

  def Asin=(value)
    @asin = value
  end

  def ExchangeId
    @exchangeId
  end

  def ExchangeId=(value)
    @exchangeId = value
  end

  def Quantity
    @quantity
  end

  def Quantity=(value)
    @quantity = value
  end

  def initialize(asin = nil,
      exchangeId = nil,
      quantity = nil)
    @asin = asin
    @exchangeId = exchangeId
    @quantity = quantity
  end
end

# http://soap.amazon.com
class ShoppingCart
  @@schema_type = "ShoppingCart"
  @@schema_ns = "http://soap.amazon.com"

  def CartId
    @cartId
  end

  def CartId=(value)
    @cartId = value
  end

  def HMAC
    @hMAC
  end

  def HMAC=(value)
    @hMAC = value
  end

  def PurchaseUrl
    @purchaseUrl
  end

  def PurchaseUrl=(value)
    @purchaseUrl = value
  end

  def Items
    @items
  end

  def Items=(value)
    @items = value
  end

  def initialize(cartId = nil,
      hMAC = nil,
      purchaseUrl = nil,
      items = nil)
    @cartId = cartId
    @hMAC = hMAC
    @purchaseUrl = purchaseUrl
    @items = items
  end
end

# http://soap.amazon.com
class GetShoppingCartRequest
  @@schema_type = "GetShoppingCartRequest"
  @@schema_ns = "http://soap.amazon.com"

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def CartId
    @cartId
  end

  def CartId=(value)
    @cartId = value
  end

  def HMAC
    @hMAC
  end

  def HMAC=(value)
    @hMAC = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(tag = nil,
      devtag = nil,
      cartId = nil,
      hMAC = nil,
      locale = nil)
    @tag = tag
    @devtag = devtag
    @cartId = cartId
    @hMAC = hMAC
    @locale = locale
  end
end

# http://soap.amazon.com
class ClearShoppingCartRequest
  @@schema_type = "ClearShoppingCartRequest"
  @@schema_ns = "http://soap.amazon.com"

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def CartId
    @cartId
  end

  def CartId=(value)
    @cartId = value
  end

  def HMAC
    @hMAC
  end

  def HMAC=(value)
    @hMAC = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(tag = nil,
      devtag = nil,
      cartId = nil,
      hMAC = nil,
      locale = nil)
    @tag = tag
    @devtag = devtag
    @cartId = cartId
    @hMAC = hMAC
    @locale = locale
  end
end

# http://soap.amazon.com
class AddShoppingCartItemsRequest
  @@schema_type = "AddShoppingCartItemsRequest"
  @@schema_ns = "http://soap.amazon.com"

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def CartId
    @cartId
  end

  def CartId=(value)
    @cartId = value
  end

  def HMAC
    @hMAC
  end

  def HMAC=(value)
    @hMAC = value
  end

  def Items
    @items
  end

  def Items=(value)
    @items = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(tag = nil,
      devtag = nil,
      cartId = nil,
      hMAC = nil,
      items = nil,
      locale = nil)
    @tag = tag
    @devtag = devtag
    @cartId = cartId
    @hMAC = hMAC
    @items = items
    @locale = locale
  end
end

# http://soap.amazon.com
class RemoveShoppingCartItemsRequest
  @@schema_type = "RemoveShoppingCartItemsRequest"
  @@schema_ns = "http://soap.amazon.com"

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def CartId
    @cartId
  end

  def CartId=(value)
    @cartId = value
  end

  def HMAC
    @hMAC
  end

  def HMAC=(value)
    @hMAC = value
  end

  def Items
    @items
  end

  def Items=(value)
    @items = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(tag = nil,
      devtag = nil,
      cartId = nil,
      hMAC = nil,
      items = nil,
      locale = nil)
    @tag = tag
    @devtag = devtag
    @cartId = cartId
    @hMAC = hMAC
    @items = items
    @locale = locale
  end
end

# http://soap.amazon.com
class ModifyShoppingCartItemsRequest
  @@schema_type = "ModifyShoppingCartItemsRequest"
  @@schema_ns = "http://soap.amazon.com"

  def tag
    @tag
  end

  def tag=(value)
    @tag = value
  end

  def devtag
    @devtag
  end

  def devtag=(value)
    @devtag = value
  end

  def CartId
    @cartId
  end

  def CartId=(value)
    @cartId = value
  end

  def HMAC
    @hMAC
  end

  def HMAC=(value)
    @hMAC = value
  end

  def Items
    @items
  end

  def Items=(value)
    @items = value
  end

  def locale
    @locale
  end

  def locale=(value)
    @locale = value
  end

  def initialize(tag = nil,
      devtag = nil,
      cartId = nil,
      hMAC = nil,
      items = nil,
      locale = nil)
    @tag = tag
    @devtag = devtag
    @cartId = cartId
    @hMAC = hMAC
    @items = items
    @locale = locale
  end
end

