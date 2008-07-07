require 'test/unit'
require 'soap/marshal'
dir = File.join(File.dirname(File.expand_path(__FILE__)), '../../ruby')
orgpath = $:.dup
begin
  $:.push(dir)
  require 'marshaltestlib'
ensure
  $:.replace(orgpath)
end

module SOAP
module Marshal
class TestMarshal < Test::Unit::TestCase
  include MarshalTestLib

  def encode(o)
    SOAPMarshal.dump(o)
  end

  def decode(s)
    SOAPMarshal.load(s)
  end
end
end
end
