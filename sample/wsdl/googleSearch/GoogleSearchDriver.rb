require 'GoogleSearch.rb'

require 'soap/rpc/driver'

class GoogleSearchPort < SOAP::RPC::Driver
  MappingRegistry = ::SOAP::Mapping::Registry.new

  MappingRegistry.set(
    GoogleSearchResult,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("urn:GoogleSearch", "GoogleSearchResult") }
  )
  MappingRegistry.set(
    ResultElementArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("urn:GoogleSearch", "ResultElement") }
  )
  MappingRegistry.set(
    DirectoryCategoryArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("urn:GoogleSearch", "DirectoryCategory") }
  )
  MappingRegistry.set(
    ResultElement,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("urn:GoogleSearch", "ResultElement") }
  )
  MappingRegistry.set(
    DirectoryCategory,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("urn:GoogleSearch", "DirectoryCategory") }
  )
  
  Methods = [
    ["doGetCachedPage", "doGetCachedPage", [
      ["in", "key",
       [SOAP::SOAPString]],
      ["in", "url",
       [SOAP::SOAPString]],
      ["retval", "return",
       [SOAP::SOAPBase64]]],
     "urn:GoogleSearchAction", "urn:GoogleSearch"],
    ["doSpellingSuggestion", "doSpellingSuggestion", [
      ["in", "key",
       [SOAP::SOAPString]],
      ["in", "phrase",
       [SOAP::SOAPString]],
      ["retval", "return",
       [SOAP::SOAPString]]],
     "urn:GoogleSearchAction", "urn:GoogleSearch"],
    ["doGoogleSearch", "doGoogleSearch", [
      ["in", "key",
       [SOAP::SOAPString]],
      ["in", "q",
       [SOAP::SOAPString]],
      ["in", "start",
       [SOAP::SOAPInt]],
      ["in", "maxResults",
       [SOAP::SOAPInt]],
      ["in", "filter",
       [SOAP::SOAPBoolean]],
      ["in", "restrict",
       [SOAP::SOAPString]],
      ["in", "safeSearch",
       [SOAP::SOAPBoolean]],
      ["in", "lr",
       [SOAP::SOAPString]],
      ["in", "ie",
       [SOAP::SOAPString]],
      ["in", "oe",
       [SOAP::SOAPString]],
      ["retval", "return",
       [::SOAP::SOAPStruct, "urn:GoogleSearch", "GoogleSearchResult"]]],
     "urn:GoogleSearchAction", "urn:GoogleSearch"]
  ]

  DefaultEndpointUrl = "http://api.google.com/search/beta2"

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

