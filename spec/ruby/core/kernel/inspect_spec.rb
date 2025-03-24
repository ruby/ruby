require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#inspect" do
  it "returns a String" do
    Object.new.inspect.should be_an_instance_of(String)
  end

  ruby_bug "", ""..."3.3" do
    it "returns an ASCII String" do
      Object.new.inspect.encoding.should == Encoding::US_ASCII
    end

    it "returns an UTF-8 String if some instance variable are UTF-8" do
      obj = Object.new
      obj.instance_variable_set(:@price, "12€")
      obj.inspect.should =~ /^#<Object:0x[0-9a-f]+ @price="12€">$/
      obj.inspect.encoding.should == Encoding::UTF_8
    end

    it "returns a BINARY String if some instance variable are neither ASCII nor UTF-8" do
      obj = Object.new
      obj.instance_variable_set(:@role, "fée".encode(Encoding::ISO_8859_1))
      obj.inspect.should =~ /^#<Object:0x[0-9a-f]+ @role="f\\xE9e\">$/
      obj.inspect.encoding.should == Encoding::BINARY
    end
  end

  it "does not call #to_s if it is defined" do
    # We must use a bare Object here
    obj = Object.new
    inspected = obj.inspect

    obj.stub!(:to_s).and_return("to_s'd")

    obj.inspect.should == inspected
  end

  it "returns a String with the object class and object_id encoded" do
    obj = Object.new
    obj.inspect.should =~ /^#<Object:0x[0-9a-f]+>$/
  end

  it "returns a String for an object without #class method" do
    obj = Object.new
    class << obj
      undef_method :class
    end
    obj.inspect.should be_kind_of(String)
  end
end
