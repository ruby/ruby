require_relative '../../spec_helper'
require 'rbconfig'

describe "RbConfig::CONFIG['UNICODE_VERSION']" do
  ruby_version_is ""..."3.4" do
    it "is 15.0.0" do
      RbConfig::CONFIG['UNICODE_VERSION'].should == "15.0.0"
    end
  end

  # Caution: ruby_version_is means is_or_later
  ruby_version_is "4.0" do
    it "is 17.0.0" do
      RbConfig::CONFIG['UNICODE_VERSION'].should == "17.0.0"
    end
  end
end
