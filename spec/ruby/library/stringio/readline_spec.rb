require_relative '../../spec_helper'
require_relative 'fixtures/classes'


describe "StringIO#readline when passed [separator]" do
  before :each do
    @io = StringIO.new("this>is>an>example")
  end

  it "returns the data read till the next occurrence of the passed separator" do
    @io.readline(">").should == "this>"
    @io.readline(">").should == "is>"
    @io.readline(">").should == "an>"
    @io.readline(">").should == "example"
  end

  it "sets $_ to the read content" do
    @io.readline(">")
    $_.should == "this>"
    @io.readline(">")
    $_.should == "is>"
    @io.readline(">")
    $_.should == "an>"
    @io.readline(">")
    $_.should == "example"
  end

  it "updates self's lineno by one" do
    @io.readline(">")
    @io.lineno.should eql(1)

    @io.readline(">")
    @io.lineno.should eql(2)

    @io.readline(">")
    @io.lineno.should eql(3)
  end

  it "returns the next paragraph when the passed separator is an empty String" do
    io = StringIO.new("this is\n\nan example")
    io.readline("").should == "this is\n\n"
    io.readline("").should == "an example"
  end

  it "returns the remaining content starting at the current position when passed nil" do
    io = StringIO.new("this is\n\nan example")
    io.pos = 5
    io.readline(nil).should == "is\n\nan example"
  end

  it "tries to convert the passed separator to a String using #to_str" do
    obj = mock('to_str')
    obj.should_receive(:to_str).and_return(">")
    @io.readline(obj).should == "this>"
  end
end

describe "StringIO#readline when passed no argument" do
  before :each do
    @io = StringIO.new("this is\nan example\nfor StringIO#readline")
  end

  it "returns the data read till the next occurrence of $/ or till eof" do
    @io.readline.should == "this is\n"

    begin
      old_sep = $/
      suppress_warning {$/ = " "}
      @io.readline.should == "an "
      @io.readline.should == "example\nfor "
      @io.readline.should == "StringIO#readline"
    ensure
      suppress_warning {$/ = old_sep}
    end
  end

  it "sets $_ to the read content" do
    @io.readline
    $_.should == "this is\n"
    @io.readline
    $_.should == "an example\n"
    @io.readline
    $_.should == "for StringIO#readline"
  end

  it "updates self's position" do
    @io.readline
    @io.pos.should eql(8)

    @io.readline
    @io.pos.should eql(19)

    @io.readline
    @io.pos.should eql(40)
  end

  it "updates self's lineno" do
    @io.readline
    @io.lineno.should eql(1)

    @io.readline
    @io.lineno.should eql(2)

    @io.readline
    @io.lineno.should eql(3)
  end

  it "raises an IOError if self is at the end" do
    @io.pos = 40
    -> { @io.readline }.should raise_error(IOError)
  end
end

describe "StringIO#readline when in write-only mode" do
  it "raises an IOError" do
    io = StringIO.new(+"xyz", "w")
    -> { io.readline }.should raise_error(IOError)

    io = StringIO.new("xyz")
    io.close_read
    -> { io.readline }.should raise_error(IOError)
  end
end

describe "StringIO#readline when passed [chomp]" do
  it "returns the data read without a trailing newline character" do
    io = StringIO.new("this>is>an>example\n")
    io.readline(chomp: true).should == "this>is>an>example"
  end
end

describe "StringIO#readline when passed [limit]" do
  before :each do
    @io = StringIO.new("this>is>an>example")
  end

  it "returns the data read until the limit is met" do
    io = StringIO.new("this>is>an>example\n")
    io.readline(3).should == "thi"
  end

  it "returns a blank string when passed a limit of 0" do
    @io.readline(0).should == ""
  end

  it "ignores it when the limit is negative" do
    seen = []
    @io.readline(-4).should == "this>is>an>example"
  end
end
