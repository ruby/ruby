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

  ruby_version_is "2.7"..."3.1" do
    it "is 12.1 for Ruby 2.7 and 3.0" do
      RbConfig::CONFIG['UNICODE_EMOJI_VERSION'].should == "12.1"
    end
  end

  ruby_version_is "3.1"..."3.2" do
    it "is 13.1 for Ruby 3.1" do
      RbConfig::CONFIG['UNICODE_EMOJI_VERSION'].should == "13.1"
    end
  end

  # Caution: ruby_version_is means is_or_later
  ruby_version_is "3.2" do
    it "is 14.0 for Ruby 3.2 or later" do
      RbConfig::CONFIG['UNICODE_EMOJI_VERSION'].should == "14.0"
    end
  end
end
