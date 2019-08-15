require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket.gethostname" do
  it "returns the host name" do
    Socket.gethostname.should == `hostname`.strip
  end
end
