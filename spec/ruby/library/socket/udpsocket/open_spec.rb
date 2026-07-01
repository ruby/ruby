require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "UDPSocket.open" do
  after :each do
    @socket.close if @socket && !@socket.closed?
  end

  it "allows calls to open without arguments" do
    @socket = UDPSocket.open
    @socket.should.is_a?(UDPSocket)
  end
end
