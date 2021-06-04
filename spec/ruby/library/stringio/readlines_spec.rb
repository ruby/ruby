require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#readlines when passed [separator]" do
  before :each do
    @io = StringIO.new("this>is>an>example")
  end

  it "returns an Array containing lines based on the passed separator" do
    @io.readlines(">").should == ["this>", "is>", "an>", "example"]
  end

  it "updates self's position based on the number of read bytes" do
    @io.readlines(">")
    @io.pos.should eql(18)
  end

  it "updates self's lineno based on the number of read lines" do
    @io.readlines(">")
    @io.lineno.should eql(4)
  end

  it "does not change $_" do
    $_ = "test"
    @io.readlines(">")
    $_.should == "test"
  end

  it "returns an Array containing all paragraphs when the passed separator is an empty String" do
    io = StringIO.new("this is\n\nan example")
    io.readlines("").should == ["this is\n\n", "an example"]
  end

  it "returns the remaining content as one line starting at the current position when passed nil" do
    io = StringIO.new("this is\n\nan example")
    io.pos = 5
    io.readlines(nil).should == ["is\n\nan example"]
  end

  it "tries to convert the passed separator to a String using #to_str" do
    obj = mock('to_str')
    obj.stub!(:to_str).and_return(">")
    @io.readlines(obj).should == ["this>", "is>", "an>", "example"]
  end
end

describe "StringIO#readlines when passed no argument" do
  before :each do
    @io = StringIO.new("this is\nan example\nfor StringIO#readlines")
  end

  it "returns an Array containing lines based on $/" do
    begin
      old_sep = $/;
      suppress_warning {$/ = " "}
      @io.readlines.should == ["this ", "is\nan ", "example\nfor ", "StringIO#readlines"]
    ensure
      suppress_warning {$/ = old_sep}
    end
  end

  it "updates self's position based on the number of read bytes" do
    @io.readlines
    @io.pos.should eql(41)
  end

  it "updates self's lineno based on the number of read lines" do
    @io.readlines
    @io.lineno.should eql(3)
  end

  it "does not change $_" do
    $_ = "test"
    @io.readlines(">")
    $_.should == "test"
  end

  it "returns an empty Array when self is at the end" do
    @io.pos = 41
    @io.readlines.should == []
  end
end

describe "StringIO#readlines when in write-only mode" do
  it "raises an IOError" do
    io = StringIO.new("xyz", "w")
    -> { io.readlines }.should raise_error(IOError)

    io = StringIO.new("xyz")
    io.close_read
    -> { io.readlines }.should raise_error(IOError)
  end
end

describe "StringIO#readlines when passed [chomp]" do
  it "returns the data read without a trailing newline character" do
    io = StringIO.new("this>is\nan>example\r\n")
    io.readlines(chomp: true).should == ["this>is", "an>example"]
  end
end
