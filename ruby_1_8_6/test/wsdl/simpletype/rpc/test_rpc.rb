require 'test/unit'
require 'wsdl/parser'
require 'wsdl/soap/wsdl2ruby'


module WSDL; module SimpleType


class TestRPC < Test::Unit::TestCase
  DIR = File.dirname(File.expand_path(__FILE__))
  def pathname(filename)
    File.join(DIR, filename)
  end

  def test_rpc
    gen = WSDL::SOAP::WSDL2Ruby.new
    gen.location = pathname("rpc.wsdl")
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
    compare("expectedEchoVersion.rb", "echo_version.rb")
    compare("expectedDriver.rb", "echo_versionDriver.rb")
    compare("expectedService.rb", "echo_version_service.rb")
    compare("expectedClient.rb", "echo_version_serviceClient.rb")
    compare("expectedServant.rb", "echo_versionServant.rb")

    File.unlink(pathname("echo_version.rb"))
    File.unlink(pathname("echo_versionDriver.rb"))
    File.unlink(pathname("echo_version_service.rb"))
    File.unlink(pathname("echo_version_serviceClient.rb"))
    File.unlink(pathname("echo_versionServant.rb"))
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
