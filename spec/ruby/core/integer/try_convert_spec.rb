require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "3.1" do
  describe "Integer.try_convert" do
    it "returns the argument if it's an Integer" do
      x = 42
      Integer.try_convert(x).should equal(x)
    end

    it "returns nil when the argument does not respond to #to_int" do
      Integer.try_convert(Object.new).should be_nil
    end

    it "sends #to_int to the argument and returns the result if it's nil" do
      obj = mock("to_int")
      obj.should_receive(:to_int).and_return(nil)
      Integer.try_convert(obj).should be_nil
    end

    it "sends #to_int to the argument and returns the result if it's an Integer" do
      x = 234
      obj = mock("to_int")
      obj.should_receive(:to_int).and_return(x)
      Integer.try_convert(obj).should equal(x)
    end

    it "sends #to_int to the argument and raises TypeError if it's not a kind of Integer" do
      obj = mock("to_int")
      obj.should_receive(:to_int).and_return(Object.new)
      -> {
        Integer.try_convert obj
      }.should raise_error(TypeError, "can't convert MockObject to Integer (MockObject#to_int gives Object)")
    end

    it "responds with a different error message when it raises a TypeError, depending on the type of the non-Integer object :to_int returns" do
      obj = mock("to_int")
      obj.should_receive(:to_int).and_return("A String")
      -> {
        Integer.try_convert obj
      }.should raise_error(TypeError, "can't convert MockObject to Integer (MockObject#to_int gives String)")
    end

    it "does not rescue exceptions raised by #to_int" do
      obj = mock("to_int")
      obj.should_receive(:to_int).and_raise(RuntimeError)
      -> { Integer.try_convert obj }.should raise_error(RuntimeError)
    end
  end
end
