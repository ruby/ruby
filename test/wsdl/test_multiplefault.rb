require 'test/unit'
require 'wsdl/parser'
require 'wsdl/soap/classDefCreator'


module WSDL


class TestMultipleFault < Test::Unit::TestCase
  def self.setup(filename)
    @@filename = filename
  end

  def test_multiplefault
    @wsdl = WSDL::Parser.new.parse(File.open(@@filename) { |f| f.read })
    classdefstr = WSDL::SOAP::ClassDefCreator.new(@wsdl).dump
    yield_eval_binding(classdefstr) do |b|
      assert_equal(
	WSDL::TestMultipleFault::AuthenticationError,
	eval("AuthenticationError", b)
      )
      assert_equal(
	WSDL::TestMultipleFault::AuthorizationError,
	eval("AuthorizationError", b)
      )
    end
  end

  def yield_eval_binding(evaled)
    b = binding
    eval(evaled, b)
    yield(b)
  end
end

TestMultipleFault.setup(File.join(File.dirname(__FILE__), 'multiplefault.wsdl'))


end
