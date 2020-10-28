require_relative '../../spec_helper'

describe "StandardError" do
  it "rescues StandardError" do
    begin
      raise StandardError
    rescue => exception
      exception.class.should == StandardError
    end
  end

  it "rescues subclass of StandardError" do
    begin
      raise RuntimeError
    rescue => exception
      exception.class.should == RuntimeError
    end
  end

  it "does not rescue superclass of StandardError" do
    -> { begin; raise Exception; rescue; end }.should raise_error(Exception)
  end
end
