require_relative '../../spec_helper'
require 'rbconfig'

describe "RbConfig::CONFIG['UNICODE_EMOJI_VERSION']" do
  ruby_version_is ""..."3.2" do
    it "is 13.1" do
      RbConfig::CONFIG['UNICODE_EMOJI_VERSION'].should == "13.1"
    end
  end

  ruby_version_is "3.2"..."3.4" do
    it "is 15.0" do
      RbConfig::CONFIG['UNICODE_EMOJI_VERSION'].should == "15.0"
    end
  end

  # Caution: ruby_version_is means is_or_later
  ruby_version_is "3.5" do
    it "is 15.1" do
      RbConfig::CONFIG['UNICODE_EMOJI_VERSION'].should == "15.1"
    end
  end
end
