require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#inspect" do
  it "returns a string" do
    [1, 2, 3].inspect.should.instance_of?(String)
  end

  it "returns '[]' for an empty Array" do
    [].inspect.should == "[]"
  end

  it "calls inspect on its elements and joins the results with commas" do
    items = Array.new(3) do |i|
      obj = mock(i.to_s)
      obj.should_receive(:inspect).and_return(i.to_s)
      obj
    end
    items.inspect.should == "[0, 1, 2]"
  end

  it "does not call #to_s on a String returned from #inspect" do
    str = +"abc"
    str.should_not_receive(:to_s)

    [str].inspect.should == '["abc"]'
  end

  it "calls #to_s on the object returned from #inspect if the Object isn't a String" do
    obj = mock("Array#inspect/to_s calls #to_s")
    obj.should_receive(:inspect).and_return(obj)
    obj.should_receive(:to_s).and_return("abc")

    [obj].inspect.should == "[abc]"
  end

  it "does not call #to_str on the object returned from #inspect when it is not a String" do
    obj = mock("Array#inspect/to_s does not call #to_str")
    obj.should_receive(:inspect).and_return(obj)
    obj.should_not_receive(:to_str)

    [obj].inspect.should =~ /^\[#<MockObject:0x[0-9a-f]+>\]$/
  end

  it "does not call #to_str on the object returned from #to_s when it is not a String" do
    obj = mock("Array#inspect/to_s does not call #to_str on #to_s result")
    obj.should_receive(:inspect).and_return(obj)
    obj.should_receive(:to_s).and_return(obj)
    obj.should_not_receive(:to_str)

    [obj].inspect.should =~ /^\[#<MockObject:0x[0-9a-f]+>\]$/
  end

  it "does not swallow exceptions raised by #to_s" do
    obj = mock("Array#inspect/to_s does not swallow #to_s exceptions")
    obj.should_receive(:inspect).and_return(obj)
    obj.should_receive(:to_s).and_raise(Exception)

    -> { [obj].inspect }.should.raise(Exception)
  end

  it "represents a recursive element with '[...]'" do
    ArraySpecs.recursive_array.inspect.should == "[1, \"two\", 3.0, [...], [...], [...], [...], [...]]"
    ArraySpecs.head_recursive_array.inspect.should == "[[...], [...], [...], [...], [...], 1, \"two\", 3.0]"
    ArraySpecs.empty_recursive_array.inspect.should == "[[...]]"
  end

  describe "with encoding" do
    before :each do
      @default_external_encoding = Encoding.default_external
    end

    after :each do
      Encoding.default_external = @default_external_encoding
    end

    it "returns a US-ASCII string for an empty Array" do
      [].inspect.encoding.should == Encoding::US_ASCII
    end

    it "use the default external encoding if it is ascii compatible" do
      Encoding.default_external = Encoding.find('UTF-8')

      utf8 = "utf8".encode("UTF-8")
      jp   = "jp".encode("EUC-JP")
      array = [jp, utf8]

      array.inspect.encoding.name.should == "UTF-8"
    end

    it "use US-ASCII encoding if the default external encoding is not ascii compatible" do
      Encoding.default_external = Encoding.find('UTF-32')

      utf8 = "utf8".encode("UTF-8")
      jp   = "jp".encode("EUC-JP")
      array = [jp, utf8]

      array.inspect.encoding.name.should == "US-ASCII"
    end

    it "does not raise if inspected result is not default external encoding" do
      utf_16be = mock(+"utf_16be")
      utf_16be.should_receive(:inspect).and_return(%<"utf_16be \u3042">.encode(Encoding::UTF_16BE))

      [utf_16be].inspect.should == '["utf_16be \u3042"]'
    end
  end
end
