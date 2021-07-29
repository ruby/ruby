require_relative '../../spec_helper'
require 'rbconfig'

describe "RbConfig::CONFIG['UNICODE_VERSION']" do
  ruby_version_is "2.6"..."2.6.2" do
    it "is 11.0.0 for Ruby 2.6.0 and 2.6.1" do
      RbConfig::CONFIG['UNICODE_VERSION'].should == "11.0.0"
    end
  end

  ruby_version_is "2.6.2"..."2.6.3" do
    it "is 12.0.0 for Ruby 2.6.2" do
      RbConfig::CONFIG['UNICODE_VERSION'].should == "12.0.0"
    end
  end

  ruby_version_is "2.6.3"..."3.1" do
    it "is 12.1.0 for Ruby 2.6.3+, Ruby 2.7, and Ruby 3.0" do
      RbConfig::CONFIG['UNICODE_VERSION'].should == "12.1.0"
    end
  end

  ruby_version_is "3.1" do
    it "is 13.0.0 for Ruby 3.1" do
      RbConfig::CONFIG['UNICODE_VERSION'].should == "13.0.0"
    end
  end
end
