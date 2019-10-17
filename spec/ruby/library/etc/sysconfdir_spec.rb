require File.expand_path('../../../spec_helper', __FILE__)
require 'etc'

describe "Etc.sysconfdir" do
  it "returns a String" do
    Etc.sysconfdir.should be_an_instance_of(String)
  end
end
