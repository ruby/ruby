require_relative '../../spec_helper'
require 'etc'

describe "Etc.systmpdir" do
  it "returns a String" do
    Etc.systmpdir.should.instance_of?(String)
  end
end
