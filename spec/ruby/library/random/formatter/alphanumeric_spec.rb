require_relative '../../../spec_helper'

ruby_version_is "3.1" do
  require 'random/formatter'

  describe "Random::Formatter#alphanumeric" do
    before :each do
      @object = Object.new
      @object.extend(Random::Formatter)
      @object.define_singleton_method(:bytes) do |n|
        "\x00".b * n
      end
    end

    it "generates a random alphanumeric string" do
      @object.alphanumeric.should =~ /\A[A-Za-z0-9]+\z/
    end

    it "has a default size of 16 characters" do
      @object.alphanumeric.size.should == 16
    end

    it "accepts a 'size' argument" do
      @object.alphanumeric(10).size.should == 10
    end

    it "uses the default size if 'nil' is given as size argument" do
      @object.alphanumeric(nil).size.should == 16
    end

    it "raises an ArgumentError if the size is not numeric" do
      -> {
        @object.alphanumeric("10")
      }.should raise_error(ArgumentError)
    end

    it "does not coerce the size argument with #to_int" do
      size = mock("size")
      size.should_not_receive(:to_int)
      -> {
        @object.alphanumeric(size)
      }.should raise_error(ArgumentError)
    end

    ruby_version_is "3.3" do
      it "accepts a 'chars' argument with the output alphabet" do
        @object.alphanumeric(chars: ['a', 'b']).should =~ /\A[ab]+\z/
      end

      it "converts the elements of chars using #to_s" do
        to_s = mock("to_s")
        to_s.should_receive(:to_s).and_return("[mock to_s]")
        # Using 1 value in chars results in an infinite loop
        @object.alphanumeric(1, chars: [to_s, to_s]).should == "[mock to_s]"
      end
    end
  end
end
