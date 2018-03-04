require_relative '../../spec_helper'
require 'resolv'

describe "Resolv#getnames" do
  platform_is_not :windows do
    it "resolves 127.0.0.1" do
      res = Resolv.new([Resolv::Hosts.new])

      names = res.getnames("127.0.0.1")
      names.should_not == nil
      names.size.should > 0
    end
  end
end
