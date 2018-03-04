require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require 'socket'

describe "Addrinfo#canonname" do

  before :each do
    @addrinfos = Addrinfo.getaddrinfo("localhost", 80, :INET, :STREAM, nil, Socket::AI_CANONNAME)
  end

  it "returns the canonical name for a host" do
    canonname = @addrinfos.map { |a| a.canonname }.find { |name| name and name.include?("localhost") }
    if canonname
      canonname.should include("localhost")
    else
      canonname.should == nil
    end
  end
end
