#!/usr/bin/env ruby
require 'soap/rpc/standaloneServer'
require 'RAA.rb'

class RAABaseServicePortType
  MappingRegistry = SOAP::Mapping::Registry.new

  MappingRegistry.set(
    StringArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://www.w3.org/2001/XMLSchema", "string") }
  )
  MappingRegistry.set(
    Map,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://xml.apache.org/xml-soap", "Map") }
  )
  MappingRegistry.set(
    Category,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/", "Category") }
  )
  MappingRegistry.set(
    InfoArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/", "Info") }
  )
  MappingRegistry.set(
    Info,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/", "Info") }
  )
  MappingRegistry.set(
    Product,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/", "Product") }
  )
  MappingRegistry.set(
    Owner,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/", "Owner") }
  )
  
  Methods = [
    ["getAllListings", "getAllListings", [
      ["retval", "return",
       [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "string"]]],
     "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/"],
    ["getProductTree", "getProductTree", [
      ["retval", "return",
       [::SOAP::SOAPStruct, "http://xml.apache.org/xml-soap", "Map"]]],
     "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/"],
    ["getInfoFromCategory", "getInfoFromCategory", [
      ["in", "category",
       [::SOAP::SOAPStruct, "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/", "Category"]],
      ["retval", "return",
       [::SOAP::SOAPArray, "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/", "Info"]]],
     "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/"],
    ["getModifiedInfoSince", "getModifiedInfoSince", [
      ["in", "timeInstant",
       [SOAP::SOAPDateTime]],
      ["retval", "return",
       [::SOAP::SOAPArray, "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/", "Info"]]],
     "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/"],
    ["getInfoFromName", "getInfoFromName", [
      ["in", "productName",
       [SOAP::SOAPString]],
      ["retval", "return",
       [::SOAP::SOAPStruct, "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/", "Info"]]],
     "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/"],
    ["getInfoFromOwnerId", "getInfoFromOwnerId", [
      ["in", "ownerId",
       [SOAP::SOAPInt]],
      ["retval", "return",
       [::SOAP::SOAPArray, "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/", "Info"]]],
     "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/"]
  ]

  def getAllListings
    ["ruby", "soap4r"]
  end
end

class RAABaseServiceServer < SOAP::RPC::StandaloneServer
  def initialize(*arg)
    super

    servant = RAABaseServicePortType.new
    RAABaseServicePortType::Methods.each do |name_as, name, params, soapaction, namespace|
      qname = XSD::QName.new(namespace, name_as)
      @router.add_method(servant, qname, soapaction, name, params)
    end

    self.mapping_registry = RAABaseServicePortType::MappingRegistry
  end
end
