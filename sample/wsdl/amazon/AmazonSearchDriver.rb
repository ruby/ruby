require 'AmazonSearch.rb'

require 'soap/rpc/driver'

class AmazonSearchPort < ::SOAP::RPC::Driver
  DefaultEndpointUrl = "http://soap.amazon.com/onca/soap3"
  MappingRegistry = ::SOAP::Mapping::Registry.new

  MappingRegistry.set(
    KeywordRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "KeywordRequest") }
  )
  MappingRegistry.set(
    ProductInfo,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ProductInfo") }
  )
  MappingRegistry.set(
    DetailsArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "Details") }
  )
  MappingRegistry.set(
    TextStreamRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "TextStreamRequest") }
  )
  MappingRegistry.set(
    PowerRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "PowerRequest") }
  )
  MappingRegistry.set(
    BrowseNodeRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "BrowseNodeRequest") }
  )
  MappingRegistry.set(
    AsinRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "AsinRequest") }
  )
  MappingRegistry.set(
    BlendedRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "BlendedRequest") }
  )
  MappingRegistry.set(
    ProductLineArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ProductLine") }
  )
  MappingRegistry.set(
    UpcRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "UpcRequest") }
  )
  MappingRegistry.set(
    SkuRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "SkuRequest") }
  )
  MappingRegistry.set(
    AuthorRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "AuthorRequest") }
  )
  MappingRegistry.set(
    ArtistRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ArtistRequest") }
  )
  MappingRegistry.set(
    ActorRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ActorRequest") }
  )
  MappingRegistry.set(
    ManufacturerRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ManufacturerRequest") }
  )
  MappingRegistry.set(
    DirectorRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "DirectorRequest") }
  )
  MappingRegistry.set(
    ListManiaRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ListManiaRequest") }
  )
  MappingRegistry.set(
    WishlistRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "WishlistRequest") }
  )
  MappingRegistry.set(
    ExchangeRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ExchangeRequest") }
  )
  MappingRegistry.set(
    ListingProductDetails,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ListingProductDetails") }
  )
  MappingRegistry.set(
    MarketplaceRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "MarketplaceRequest") }
  )
  MappingRegistry.set(
    MarketplaceSearch,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "MarketplaceSearch") }
  )
  MappingRegistry.set(
    MarketplaceSearchDetailsArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "MarketplaceSearchDetails") }
  )
  MappingRegistry.set(
    SellerProfileRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "SellerProfileRequest") }
  )
  MappingRegistry.set(
    SellerProfile,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "SellerProfile") }
  )
  MappingRegistry.set(
    SellerProfileDetailsArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "SellerProfileDetails") }
  )
  MappingRegistry.set(
    SellerRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "SellerRequest") }
  )
  MappingRegistry.set(
    SellerSearch,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "SellerSearch") }
  )
  MappingRegistry.set(
    SellerSearchDetailsArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "SellerSearchDetails") }
  )
  MappingRegistry.set(
    SimilarityRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "SimilarityRequest") }
  )
  MappingRegistry.set(
    GetShoppingCartRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "GetShoppingCartRequest") }
  )
  MappingRegistry.set(
    ShoppingCart,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ShoppingCart") }
  )
  MappingRegistry.set(
    ItemArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "Item") }
  )
  MappingRegistry.set(
    SimilarProductsArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://www.w3.org/2001/XMLSchema", "string") }
  )
  MappingRegistry.set(
    ClearShoppingCartRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ClearShoppingCartRequest") }
  )
  MappingRegistry.set(
    AddShoppingCartItemsRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "AddShoppingCartItemsRequest") }
  )
  MappingRegistry.set(
    AddItemArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "AddItem") }
  )
  MappingRegistry.set(
    RemoveShoppingCartItemsRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "RemoveShoppingCartItemsRequest") }
  )
  MappingRegistry.set(
    ItemIdArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://www.w3.org/2001/XMLSchema", "string") }
  )
  MappingRegistry.set(
    ModifyShoppingCartItemsRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ModifyShoppingCartItemsRequest") }
  )
  MappingRegistry.set(
    ItemQuantityArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ItemQuantity") }
  )
  MappingRegistry.set(
    GetTransactionDetailsRequest,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "GetTransactionDetailsRequest") }
  )
  MappingRegistry.set(
    OrderIdArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://www.w3.org/2001/XMLSchema", "string") }
  )
  MappingRegistry.set(
    GetTransactionDetailsResponse,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "GetTransactionDetailsResponse") }
  )
  MappingRegistry.set(
    ShortSummaryArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ShortSummary") }
  )
  MappingRegistry.set(
    Details,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "Details") }
  )
  MappingRegistry.set(
    ProductLine,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ProductLine") }
  )
  MappingRegistry.set(
    MarketplaceSearchDetails,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "MarketplaceSearchDetails") }
  )
  MappingRegistry.set(
    SellerProfileDetails,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "SellerProfileDetails") }
  )
  MappingRegistry.set(
    SellerSearchDetails,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "SellerSearchDetails") }
  )
  MappingRegistry.set(
    Item,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "Item") }
  )
  MappingRegistry.set(
    AddItem,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "AddItem") }
  )
  MappingRegistry.set(
    ItemQuantity,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ItemQuantity") }
  )
  MappingRegistry.set(
    ShortSummary,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://soap.amazon.com", "ShortSummary") }
  )
  
  Methods = [
    ["KeywordSearchRequest", "keywordSearchRequest",
      [
        ["in", "KeywordSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "KeywordRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["TextStreamSearchRequest", "textStreamSearchRequest",
      [
        ["in", "TextStreamSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "TextStreamRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["PowerSearchRequest", "powerSearchRequest",
      [
        ["in", "PowerSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "PowerRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["BrowseNodeSearchRequest", "browseNodeSearchRequest",
      [
        ["in", "BrowseNodeSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "BrowseNodeRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["AsinSearchRequest", "asinSearchRequest",
      [
        ["in", "AsinSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "AsinRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["BlendedSearchRequest", "blendedSearchRequest",
      [
        ["in", "BlendedSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "BlendedRequest"]],
        ["retval", "return", [::SOAP::SOAPArray, "http://soap.amazon.com", "ProductLine"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["UpcSearchRequest", "upcSearchRequest",
      [
        ["in", "UpcSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "UpcRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["SkuSearchRequest", "skuSearchRequest",
      [
        ["in", "SkuSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "SkuRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["AuthorSearchRequest", "authorSearchRequest",
      [
        ["in", "AuthorSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "AuthorRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["ArtistSearchRequest", "artistSearchRequest",
      [
        ["in", "ArtistSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ArtistRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["ActorSearchRequest", "actorSearchRequest",
      [
        ["in", "ActorSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ActorRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["ManufacturerSearchRequest", "manufacturerSearchRequest",
      [
        ["in", "ManufacturerSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ManufacturerRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["DirectorSearchRequest", "directorSearchRequest",
      [
        ["in", "DirectorSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "DirectorRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["ListManiaSearchRequest", "listManiaSearchRequest",
      [
        ["in", "ListManiaSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ListManiaRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["WishlistSearchRequest", "wishlistSearchRequest",
      [
        ["in", "WishlistSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "WishlistRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["ExchangeSearchRequest", "exchangeSearchRequest",
      [
        ["in", "ExchangeSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ExchangeRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ListingProductDetails"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["MarketplaceSearchRequest", "marketplaceSearchRequest",
      [
        ["in", "MarketplaceSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "MarketplaceRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "MarketplaceSearch"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["SellerProfileSearchRequest", "sellerProfileSearchRequest",
      [
        ["in", "SellerProfileSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "SellerProfileRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "SellerProfile"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["SellerSearchRequest", "sellerSearchRequest",
      [
        ["in", "SellerSearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "SellerRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "SellerSearch"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["SimilaritySearchRequest", "similaritySearchRequest",
      [
        ["in", "SimilaritySearchRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "SimilarityRequest"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ProductInfo"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["GetShoppingCartRequest", "getShoppingCartRequest",
      [
        ["in", "GetShoppingCartRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "GetShoppingCartRequest"]],
        ["retval", "ShoppingCart", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ShoppingCart"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["ClearShoppingCartRequest", "clearShoppingCartRequest",
      [
        ["in", "ClearShoppingCartRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ClearShoppingCartRequest"]],
        ["retval", "ShoppingCart", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ShoppingCart"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["AddShoppingCartItemsRequest", "addShoppingCartItemsRequest",
      [
        ["in", "AddShoppingCartItemsRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "AddShoppingCartItemsRequest"]],
        ["retval", "ShoppingCart", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ShoppingCart"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["RemoveShoppingCartItemsRequest", "removeShoppingCartItemsRequest",
      [
        ["in", "RemoveShoppingCartItemsRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "RemoveShoppingCartItemsRequest"]],
        ["retval", "ShoppingCart", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ShoppingCart"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["ModifyShoppingCartItemsRequest", "modifyShoppingCartItemsRequest",
      [
        ["in", "ModifyShoppingCartItemsRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ModifyShoppingCartItemsRequest"]],
        ["retval", "ShoppingCart", [::SOAP::SOAPStruct, "http://soap.amazon.com", "ShoppingCart"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ],
    ["GetTransactionDetailsRequest", "getTransactionDetailsRequest",
      [
        ["in", "GetTransactionDetailsRequest", [::SOAP::SOAPStruct, "http://soap.amazon.com", "GetTransactionDetailsRequest"]],
        ["retval", "GetTransactionDetailsResponse", [::SOAP::SOAPStruct, "http://soap.amazon.com", "GetTransactionDetailsResponse"]]
      ],
      "http://soap.amazon.com", "http://soap.amazon.com"
    ]
  ]

  def initialize(endpoint_url = nil)
    endpoint_url ||= DefaultEndpointUrl
    super(endpoint_url, nil)
    self.mapping_registry = MappingRegistry
    init_methods
  end

private

  def init_methods
    Methods.each do |name_as, name, params, soapaction, namespace|
      qname = XSD::QName.new(namespace, name_as)
      @proxy.add_method(qname, soapaction, name, params)
      add_rpc_method_interface(name, params)
    end
  end
end

