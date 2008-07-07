require 'test/unit'
require 'soap/rpc/standaloneServer'
require 'soap/wsdlDriver'
require 'wsdl/soap/wsdl2ruby'


module WSDL
module Ref


class TestRef < Test::Unit::TestCase
  DIR = File.dirname(File.expand_path(__FILE__))
  Port = 17171

  def test_classdef
    gen = WSDL::SOAP::WSDL2Ruby.new
    gen.location = pathname("product.wsdl")
    gen.basedir = DIR
    gen.logger.level = Logger::FATAL
    gen.opt['classdef'] = nil
    gen.opt['force'] = true
    suppress_warning do
      gen.run
    end
    compare("expectedProduct.rb", "product.rb")
    File.unlink(pathname('product.rb'))
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

  def suppress_warning
    back = $VERBOSE
    $VERBOSE = nil
    begin
      yield
    ensure
      $VERBOSE = back
    end
  end
end


end
end
