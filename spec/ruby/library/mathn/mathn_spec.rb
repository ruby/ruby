require File.expand_path('../../../spec_helper', __FILE__)

describe "mathn" do
  ruby_version_is "2.5" do
    it "is no longer part of the standard library" do
      -> { require "mathn" }.should raise_error(LoadError)
    end
  end
end
