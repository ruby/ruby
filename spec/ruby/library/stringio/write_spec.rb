require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/write'

describe "StringIO#write when passed [Object]" do
  it_behaves_like :stringio_write, :write
end

describe "StringIO#write when passed [String]" do
  it_behaves_like :stringio_write_string, :write
end

describe "StringIO#write when self is not writable" do
  it_behaves_like :stringio_write_not_writable, :write
end

describe "StringIO#write when in append mode" do
  it_behaves_like :stringio_write_append, :write
end

describe "StringIO#write when passed multiple arguments" do
  before :each do
    @io = StringIO.new(+"12345")
  end

  it "accepts multiple arguments" do
    @io.write("foo", "bar").should == 6
    @io.string.should == "foobar"
    @io.pos.should == 6
  end

  it "appends each argument to the end when in append mode" do
    io = StringIO.new(+"example", "a")
    io.write(", just", " testing").should == 14
    io.string.should == "example, just testing"
    io.pos.should == 21
  end

  it "coerces each argument to a String using #to_s" do
    obj1 = mock("to_s 1")
    obj1.should_receive(:to_s).and_return("foo")
    obj2 = mock("to_s 2")
    obj2.should_receive(:to_s).and_return("bar")
    @io.write(obj1, obj2).should == 6
    @io.string.should == "foobar"
  end
end
