require_relative '../../spec_helper'
require 'etc'

describe "Etc.uname" do
  it "returns a Hash with the documented keys" do
    uname = Etc.uname
    uname.should be_kind_of(Hash)
    uname.should.key?(:sysname)
    uname.should.key?(:nodename)
    uname.should.key?(:release)
    uname.should.key?(:version)
    uname.should.key?(:machine)
  end
end
