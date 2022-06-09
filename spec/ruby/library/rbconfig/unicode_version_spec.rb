require_relative '../../spec_helper'
require 'rbconfig'

describe "RbConfig::CONFIG['UNICODE_VERSION']" do
  ruby_version_is ""..."3.1" do
    it "is 12.1.0" do
      RbConfig::CONFIG['UNICODE_VERSION'].should == "12.1.0"
    end
  end

  ruby_version_is "3.1"..."3.2" do
    it "is 13.0.0" do
      RbConfig::CONFIG['UNICODE_VERSION'].should == "13.0.0"
    end
  end

  # Caution: ruby_version_is means is_or_later
  ruby_version_is "3.2" do
    it "is 14.0.0" do
      RbConfig::CONFIG['UNICODE_VERSION'].should == "14.0.0"
    end
  end
end
