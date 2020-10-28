require_relative '../../spec_helper'
require 'rbconfig'

describe "RbConfig::CONFIG['UNICODE_EMOJI_VERSION']" do
  ruby_version_is "2.6"..."2.6.2" do
    it "is 11.0 for Ruby 2.6.0 and 2.6.1" do
      RbConfig::CONFIG['UNICODE_EMOJI_VERSION'].should == "11.0"
    end
  end

  ruby_version_is "2.6.2"..."2.7" do
    it "is 12.0 for Ruby 2.6.2+" do
      RbConfig::CONFIG['UNICODE_EMOJI_VERSION'].should == "12.0"
    end
  end

  ruby_version_is "2.7" do
    it "is 12.1 for Ruby 2.7" do
      RbConfig::CONFIG['UNICODE_EMOJI_VERSION'].should == "12.1"
    end
  end
end
