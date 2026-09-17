require_relative '../../spec_helper'
require_relative '../enumerable/shared/enumeratorized'

describe "ENV.each_key" do

  it "returns each key" do
    e = []
    orig = ENV.to_hash
    begin
      ENV.clear
      ENV["1"] = "3"
      ENV["2"] = "4"
      ENV.each_key { |k| e << k }.should.equal?(ENV)
      e.should.include?("1")
      e.should.include?("2")
    ensure
      ENV.replace orig
    end
  end

  it "returns an Enumerator if called without a block" do
    enum = ENV.each_key
    enum.should.instance_of?(Enumerator)
    enum.to_a.should == ENV.keys
  end

  platform_is_not :windows do
    it "returns keys in the locale encoding" do
      ENV.each_key do |key|
        key.encoding.should == Encoding.find('locale')
      end
    end
  end

  # https://bugs.ruby-lang.org/issues/20958
  platform_is :windows do
    ruby_version_is ""..."4.1" do
      it "returns keys in the locale encoding" do
        ENV.each_key do |key|
          key.encoding.should == Encoding.find('locale')
        end
      end
    end

    ruby_version_is "4.1" do
      it "returns the keys in UTF-8" do
        ENV.each_key do |key|
          key.encoding.should == Encoding::UTF_8
        end
      end
    end
  end

  it_behaves_like :enumeratorized_with_origin_size, :each_key, ENV
end
