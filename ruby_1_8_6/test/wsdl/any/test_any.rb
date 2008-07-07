require 'test/unit'
require 'wsdl/parser'
require 'wsdl/soap/wsdl2ruby'
module WSDL; module Any


class TestAny < Test::Unit::TestCase
  DIR = File.dirname(File.expand_path(__FILE__))
  def pathname(filename)
    File.join(DIR, filename)
  end

  def test_any
    gen = WSDL::SOAP::WSDL2Ruby.new
    gen.location = pathname("any.wsdl")
    gen.basedir = DIR
    gen.logger.level = Logger::FATAL
    gen.opt['classdef'] = nil
    gen.opt['driver'] = nil
    gen.opt['client_skelton'] = nil
    gen.opt['servant_skelton'] = nil
    gen.opt['standalone_server_stub'] = nil
    gen.opt['force'] = true
    suppress_warning do
      gen.run
    end
    compare("expectedDriver.rb", "echoDriver.rb")
    compare("expectedEcho.rb", "echo.rb")
    compare("expectedService.rb", "echo_service.rb")

    File.unlink(pathname("echo_service.rb"))
    File.unlink(pathname("echo.rb"))
    File.unlink(pathname("echo_serviceClient.rb"))
    File.unlink(pathname("echoDriver.rb"))
    File.unlink(pathname("echoServant.rb"))
  end

  def compare(expected, actual)
    assert_equal(loadfile(expected), loadfile(actual), actual)
  end

  def loadfile(file)
    File.open(pathname(file)) { |f| f.read }
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


end; end
