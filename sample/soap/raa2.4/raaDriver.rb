require 'raa.rb'

require 'soap/rpc/driver'

class RaaServicePortType < SOAP::RPC::Driver
  TargetNamespace = "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
  MappingRegistry = ::SOAP::Mapping::Registry.new

  MappingRegistry.set(
    Gem,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/", "Gem") }
  )
  MappingRegistry.set(
    Category,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/", "Category") }
  )
  MappingRegistry.set(
    Owner,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/", "Owner") }
  )
  MappingRegistry.set(
    Project,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/", "Project") }
  )
  MappingRegistry.set(
    ProjectArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/", "Project") }
  )
  MappingRegistry.set(
    ProjectDependencyArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/", "ProjectDependency") }
  )
  MappingRegistry.set(
    StringArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://www.w3.org/2001/XMLSchema", "string") }
  )
  MappingRegistry.set(
    Map,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://www.w3.org/2001/XMLSchema", "anyType") }
  )
  MappingRegistry.set(
    OwnerArray,
    ::SOAP::SOAPArray,
    ::SOAP::Mapping::Registry::TypedArrayFactory,
    { :type => XSD::QName.new("http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/", "Owner") }
  )
  MappingRegistry.set(
    ProjectDependency,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/", "ProjectDependency") }
  )
  Methods = [
    ["gem", "gem",
      [
        ["in", "name", [SOAP::SOAPString]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/", "Gem"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["dependents", "dependents",
      [
        ["in", "name", [SOAP::SOAPString]],
        ["in", "version", [SOAP::SOAPString]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/", "ProjectDependency"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["names", "names",
      [
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "string"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["size", "size",
      [
        ["retval", "return", [SOAP::SOAPInt]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["list_by_category", "list_by_category",
      [
        ["in", "major", [SOAP::SOAPString]],
        ["in", "minor", [SOAP::SOAPString]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "string"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["tree_by_category", "tree_by_category",
      [
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "anyType"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["list_recent_updated", "list_recent_updated",
      [
        ["in", "idx", [SOAP::SOAPInt]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "string"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["list_recent_created", "list_recent_created",
      [
        ["in", "idx", [SOAP::SOAPInt]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "string"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["list_updated_since", "list_updated_since",
      [
        ["in", "date", [SOAP::SOAPDateTime]],
        ["in", "idx", [SOAP::SOAPInt]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "string"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["list_created_since", "list_created_since",
      [
        ["in", "date", [SOAP::SOAPDateTime]],
        ["in", "idx", [SOAP::SOAPInt]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "string"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["list_by_owner", "list_by_owner",
      [
        ["in", "owner_id", [SOAP::SOAPInt]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "string"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["search_name", "search_name",
      [
        ["in", "substring", [SOAP::SOAPString]],
        ["in", "idx", [SOAP::SOAPInt]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "string"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["search_short_description", "search_short_description",
      [
        ["in", "substring", [SOAP::SOAPString]],
        ["in", "idx", [SOAP::SOAPInt]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "string"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["search_owner", "search_owner",
      [
        ["in", "substring", [SOAP::SOAPString]],
        ["in", "idx", [SOAP::SOAPInt]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "string"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["search_version", "search_version",
      [
        ["in", "substring", [SOAP::SOAPString]],
        ["in", "idx", [SOAP::SOAPInt]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "string"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["search_status", "search_status",
      [
        ["in", "substring", [SOAP::SOAPString]],
        ["in", "idx", [SOAP::SOAPInt]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "string"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["search_description", "search_description",
      [
        ["in", "substring", [SOAP::SOAPString]],
        ["in", "idx", [SOAP::SOAPInt]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "string"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["search", "search",
      [
        ["in", "substring", [SOAP::SOAPString]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.w3.org/2001/XMLSchema", "anyType"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["owner", "owner",
      [
        ["in", "owner_id", [SOAP::SOAPInt]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/", "Owner"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["list_owner", "list_owner",
      [
        ["in", "idx", [SOAP::SOAPInt]],
        ["retval", "return", [::SOAP::SOAPArray, "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/", "Owner"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["update", "update",
      [
        ["in", "name", [SOAP::SOAPString]],
        ["in", "pass", [SOAP::SOAPString]],
        ["in", "gem", [::SOAP::SOAPStruct, "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/", "Gem"]],
        ["retval", "return", [::SOAP::SOAPStruct, "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/", "Gem"]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ],
    ["update_pass", "update_pass",
      [
        ["in", "name", [SOAP::SOAPString]],
        ["in", "oldpass", [SOAP::SOAPString]],
        ["in", "newpass", [SOAP::SOAPString]]
      ],
      "", "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.4/"
    ]
  ]

  DefaultEndpointUrl = "http://raa.ruby-lang.org/soapsrv"

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

