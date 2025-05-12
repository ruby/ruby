require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe :hash_to_s, shared: true do
  it "returns a string representation with same order as each()" do
    h = { a: [1, 2], b: -2, d: -6, nil => nil }
    expected = ruby_version_is("3.4") ? "{a: [1, 2], b: -2, d: -6, nil => nil}" : "{:a=>[1, 2], :b=>-2, :d=>-6, nil=>nil}"
    h.send(@method).should == expected
  end

  it "calls #inspect on keys and values" do
    key = mock('key')
    val = mock('val')
    key.should_receive(:inspect).and_return('key')
    val.should_receive(:inspect).and_return('val')
    expected = ruby_version_is("3.4") ? "{key => val}" : "{key=>val}"
    { key => val }.send(@method).should == expected
  end

  it "does not call #to_s on a String returned from #inspect" do
    str = +"abc"
    str.should_not_receive(:to_s)
    expected = ruby_version_is("3.4") ? '{a: "abc"}' : '{:a=>"abc"}'
    { a: str }.send(@method).should == expected
  end

  it "calls #to_s on the object returned from #inspect if the Object isn't a String" do
    obj = mock("Hash#inspect/to_s calls #to_s")
    obj.should_receive(:inspect).and_return(obj)
    obj.should_receive(:to_s).and_return("abc")
    expected = ruby_version_is("3.4") ? "{a: abc}" : "{:a=>abc}"
    { a: obj }.send(@method).should == expected
  end

  it "does not call #to_str on the object returned from #inspect when it is not a String" do
    obj = mock("Hash#inspect/to_s does not call #to_str")
    obj.should_receive(:inspect).and_return(obj)
    obj.should_not_receive(:to_str)
    expected_pattern = ruby_version_is("3.4") ? /^\{a: #<MockObject:0x[0-9a-f]+>\}$/ : /^\{:a=>#<MockObject:0x[0-9a-f]+>\}$/
    { a: obj }.send(@method).should =~ expected_pattern
  end

  it "does not call #to_str on the object returned from #to_s when it is not a String" do
    obj = mock("Hash#inspect/to_s does not call #to_str on #to_s result")
    obj.should_receive(:inspect).and_return(obj)
    obj.should_receive(:to_s).and_return(obj)
    obj.should_not_receive(:to_str)
    expected_pattern = ruby_version_is("3.4") ? /^\{a: #<MockObject:0x[0-9a-f]+>\}$/ : /^\{:a=>#<MockObject:0x[0-9a-f]+>\}$/
    { a: obj }.send(@method).should =~ expected_pattern
  end

  it "does not swallow exceptions raised by #to_s" do
    obj = mock("Hash#inspect/to_s does not swallow #to_s exceptions")
    obj.should_receive(:inspect).and_return(obj)
    obj.should_receive(:to_s).and_raise(Exception)

    -> { { a: obj }.send(@method) }.should raise_error(Exception)
  end

  it "handles hashes with recursive values" do
    x = {}
    x[0] = x
    expected = ruby_version_is("3.4") ? '{0 => {...}}' : '{0=>{...}}'
    x.send(@method).should == expected

    x = {}
    y = {}
    x[0] = y
    y[1] = x
    expected_x = ruby_version_is("3.4") ? '{0 => {1 => {...}}}' : '{0=>{1=>{...}}}'
    expected_y = ruby_version_is("3.4") ? '{1 => {0 => {...}}}' : '{1=>{0=>{...}}}'
    x.send(@method).should == expected_x
    y.send(@method).should == expected_y
  end

  it "does not raise if inspected result is not default external encoding" do
    utf_16be = mock("utf_16be")
    utf_16be.should_receive(:inspect).and_return(%<"utf_16be \u3042">.encode(Encoding::UTF_16BE))
    expected = ruby_version_is("3.4") ? '{a: "utf_16be \u3042"}' : '{:a=>"utf_16be \u3042"}'
    {a: utf_16be}.send(@method).should == expected
  end

  it "works for keys and values whose #inspect return a frozen String" do
    expected = ruby_version_is("3.4") ? "{true => false}" : "{true=>false}"
    { true => false }.to_s.should == expected
  end

  ruby_version_is "3.4" do
    it "adds quotes to symbol keys that are not valid symbol literals" do
      { "needs-quotes": 1 }.send(@method).should == '{"needs-quotes": 1}'
    end
  end
end
