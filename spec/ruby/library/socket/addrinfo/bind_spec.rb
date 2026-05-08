require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Addrinfo#bind" do

  before :each do
    @addrinfo = Addrinfo.tcp("127.0.0.1", 0)
  end

  after :each do
    @socket.close unless @socket.closed?
  end

  it "returns a bound socket when no block is given" do
    @socket = @addrinfo.bind
    @socket.should.is_a?(Socket)
    @socket.closed?.should == false
  end

  it "yields the socket if a block is given" do
    @addrinfo.bind do |sock|
      @socket = sock
      sock.should.is_a?(Socket)
    end
    @socket.closed?.should == true
  end

end
