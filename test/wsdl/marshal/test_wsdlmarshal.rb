require 'test/unit'
require 'wsdl/parser'
require 'soap/mapping/wsdlencodedregistry'
require 'soap/marshal'
require 'wsdl/soap/wsdl2ruby'

class WSDLMarshaller
  include SOAP

  def initialize(wsdlfile)
    wsdl = WSDL::Parser.new.parse(File.open(wsdlfile) { |f| f.read })
    types = wsdl.collect_complextypes
    @opt = {
      :decode_typemap => types,
      :generate_explicit_type => false,
      :pretty => true
    }
    @mapping_registry = Mapping::WSDLEncodedRegistry.new(types)
  end

  def dump(obj, io = nil)
    type = Mapping.class2element(obj.class)
    ele =  Mapping.obj2soap(obj, @mapping_registry, type)
    ele.elename = ele.type
    Processor.marshal(SOAPEnvelope.new(nil, SOAPBody.new(ele)), @opt, io)
  end

  def load(io)
    header, body = Processor.unmarshal(io, @opt)
    Mapping.soap2obj(body.root_node)
  end
end


require File.join(File.dirname(__FILE__), 'person_org')

class Person
  def ==(rhs)
    @familyname == rhs.familyname and @givenname == rhs.givenname and
      @var1 == rhs.var1 and @var2 == rhs.var2 and @var3 == rhs.var3
  end
end


class TestWSDLMarshal < Test::Unit::TestCase
  DIR = File.dirname(File.expand_path(__FILE__))

  def test_marshal
    marshaller = WSDLMarshaller.new(pathname('person.wsdl'))
    obj = Person.new("NAKAMURA", "Hiroshi", 1, 1.0,  "1")
    str = marshaller.dump(obj)
    obj2 = marshaller.load(str)
    assert_equal(obj, obj2)
    assert_equal(str, marshaller.dump(obj2))
  end

  def test_classdef
    gen = WSDL::SOAP::WSDL2Ruby.new
    gen.location = pathname("person.wsdl")
    gen.basedir = DIR
    gen.logger.level = Logger::FATAL
    gen.opt['classdef'] = nil
    gen.opt['force'] = true
    gen.run
    compare("person_org.rb", "Person.rb")
    File.unlink(pathname('Person.rb'))
  end

  def compare(expected, actual)
    assert_equal(loadfile(expected), loadfile(actual), actual)
  end

  def loadfile(file)
    File.open(pathname(file)) { |f| f.read }
  end

  def pathname(filename)
    File.join(DIR, filename)
  end
end
