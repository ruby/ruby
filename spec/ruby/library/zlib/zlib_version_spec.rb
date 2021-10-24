require_relative '../../spec_helper'
require 'zlib'

describe "Zlib.zlib_version" do
  it "returns the version of the libz library" do
    Zlib.zlib_version.should be_an_instance_of(String)
  end
end
