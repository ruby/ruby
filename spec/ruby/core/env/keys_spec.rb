require_relative '../../spec_helper'

describe "ENV.keys" do

  it "returns an array of the keys" do
    ENV.keys.should == ENV.to_hash.keys
  end

  platform_is_not :windows do
    it "returns the keys in the locale encoding" do
      ENV.keys.each do |key|
        key.encoding.should == Encoding.find('locale')
      end
    end
  end

  # https://bugs.ruby-lang.org/issues/20958
  platform_is :windows do
    ruby_version_is ""..."4.1" do
      it "returns the keys in the locale encoding" do
        ENV.keys.each do |key|
          key.encoding.should == Encoding.find('locale')
        end
      end
    end

    ruby_version_is "4.1" do
      it "returns the keys in UTF-8" do
        ENV.keys.each do |key|
          key.encoding.should == Encoding::UTF_8
        end
      end
    end
  end
end
