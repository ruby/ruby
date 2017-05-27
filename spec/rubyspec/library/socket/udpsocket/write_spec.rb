require File.expand_path('../../../../spec_helper', __FILE__)
require File.expand_path('../../fixtures/classes', __FILE__)

describe "UDPSocket#write" do
  it "raises EMSGSIZE if msg is too long" do
    begin
      host, port = SocketSpecs.hostname, SocketSpecs.port
      s1 = UDPSocket.new
      s1.bind(host, port)
      s2 = UDPSocket.new
      s2.connect(host, port)

      lambda do
        s2.write('1' * 100_000)
      end.should raise_error(Errno::EMSGSIZE)
    ensure
      s1.close if s1 && !s1.closed?
      s2.close if s2 && !s2.closed?
    end
  end
end
