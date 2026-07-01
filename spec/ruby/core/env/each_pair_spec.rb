require_relative 'spec_helper'
require_relative '../enumerable/shared/enumeratorized'

describe "ENV.each_pair" do
  it "returns each pair" do
    orig = ENV.to_hash
    e = []
    begin
      ENV.clear
      ENV["foo"] = "bar"
      ENV["baz"] = "boo"
      ENV.each_pair { |k, v| e << [k, v] }.should.equal?(ENV)
      e.should.include?(["foo", "bar"])
      e.should.include?(["baz", "boo"])
    ensure
      ENV.replace orig
    end
  end

  it "returns an Enumerator if called without a block" do
    enum = ENV.each_pair
    enum.should.instance_of?(Enumerator)
    enum.each do |name, value|
      ENV[name].should == value
    end
  end

  it_behaves_like :enumeratorized_with_origin_size, :each_pair, ENV

  describe "with encoding" do
    before :each do
      @external = Encoding.default_external
      @internal = Encoding.default_internal

      Encoding.default_external = Encoding::BINARY
    end

    after :each do
      Encoding.default_external = @external
      Encoding.default_internal = @internal
    end

    it "uses the locale encoding when Encoding.default_internal is nil" do
      Encoding.default_internal = nil

      ENV.each_pair do |key, value|
        key.should.be_locale_env
        value.should.be_locale_env
      end
    end

    it "transcodes from the locale encoding to Encoding.default_internal if set" do
      Encoding.default_internal = internal = Encoding::IBM437

      ENV.each_pair do |key, value|
        key.encoding.should.equal?(internal)
        if value.ascii_only?
          value.encoding.should.equal?(internal)
        end
      end
    end
  end
end
