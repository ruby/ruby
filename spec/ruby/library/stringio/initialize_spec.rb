require_relative '../../spec_helper'
require 'stringio'

describe "StringIO#initialize when passed [Object, mode]" do
  before :each do
    @io = StringIO.allocate
  end

  it "uses the passed Object as the StringIO backend" do
    @io.send(:initialize, str = "example", "r")
    @io.string.should equal(str)
  end

  it "sets the mode based on the passed mode" do
    io = StringIO.allocate
    io.send(:initialize, "example", "r")
    io.closed_read?.should be_false
    io.closed_write?.should be_true

    io = StringIO.allocate
    io.send(:initialize, "example", "rb")
    io.closed_read?.should be_false
    io.closed_write?.should be_true

    io = StringIO.allocate
    io.send(:initialize, "example", "r+")
    io.closed_read?.should be_false
    io.closed_write?.should be_false

    io = StringIO.allocate
    io.send(:initialize, "example", "rb+")
    io.closed_read?.should be_false
    io.closed_write?.should be_false

    io = StringIO.allocate
    io.send(:initialize, "example", "w")
    io.closed_read?.should be_true
    io.closed_write?.should be_false

    io = StringIO.allocate
    io.send(:initialize, "example", "wb")
    io.closed_read?.should be_true
    io.closed_write?.should be_false

    io = StringIO.allocate
    io.send(:initialize, "example", "w+")
    io.closed_read?.should be_false
    io.closed_write?.should be_false

    io = StringIO.allocate
    io.send(:initialize, "example", "wb+")
    io.closed_read?.should be_false
    io.closed_write?.should be_false

    io = StringIO.allocate
    io.send(:initialize, "example", "a")
    io.closed_read?.should be_true
    io.closed_write?.should be_false

    io = StringIO.allocate
    io.send(:initialize, "example", "ab")
    io.closed_read?.should be_true
    io.closed_write?.should be_false

    io = StringIO.allocate
    io.send(:initialize, "example", "a+")
    io.closed_read?.should be_false
    io.closed_write?.should be_false

    io = StringIO.allocate
    io.send(:initialize, "example", "ab+")
    io.closed_read?.should be_false
    io.closed_write?.should be_false
  end

  it "allows passing the mode as an Integer" do
    io = StringIO.allocate
    io.send(:initialize, "example", IO::RDONLY)
    io.closed_read?.should be_false
    io.closed_write?.should be_true

    io = StringIO.allocate
    io.send(:initialize, "example", IO::RDWR)
    io.closed_read?.should be_false
    io.closed_write?.should be_false

    io = StringIO.allocate
    io.send(:initialize, "example", IO::WRONLY)
    io.closed_read?.should be_true
    io.closed_write?.should be_false

    io = StringIO.allocate
    io.send(:initialize, "example", IO::WRONLY | IO::TRUNC)
    io.closed_read?.should be_true
    io.closed_write?.should be_false

    io = StringIO.allocate
    io.send(:initialize, "example", IO::RDWR | IO::TRUNC)
    io.closed_read?.should be_false
    io.closed_write?.should be_false

    io = StringIO.allocate
    io.send(:initialize, "example", IO::WRONLY | IO::APPEND)
    io.closed_read?.should be_true
    io.closed_write?.should be_false

    io = StringIO.allocate
    io.send(:initialize, "example", IO::RDWR | IO::APPEND)
    io.closed_read?.should be_false
    io.closed_write?.should be_false
  end

  it "raises a #{frozen_error_class} when passed a frozen String in truncate mode as StringIO backend" do
    io = StringIO.allocate
    -> { io.send(:initialize, "example".freeze, IO::TRUNC) }.should raise_error(frozen_error_class)
  end

  it "tries to convert the passed mode to a String using #to_str" do
    obj = mock('to_str')
    obj.should_receive(:to_str).and_return("r")
    @io.send(:initialize, "example", obj)

    @io.closed_read?.should be_false
    @io.closed_write?.should be_true
  end

  it "raises an Errno::EACCES error when passed a frozen string with a write-mode" do
    (str = "example").freeze
    -> { @io.send(:initialize, str, "r+") }.should raise_error(Errno::EACCES)
    -> { @io.send(:initialize, str, "w") }.should raise_error(Errno::EACCES)
    -> { @io.send(:initialize, str, "a") }.should raise_error(Errno::EACCES)
  end
end

describe "StringIO#initialize when passed [Object]" do
  before :each do
    @io = StringIO.allocate
  end

  it "uses the passed Object as the StringIO backend" do
    @io.send(:initialize, str = "example")
    @io.string.should equal(str)
  end

  it "sets the mode to read-write" do
    @io.send(:initialize, "example")
    @io.closed_read?.should be_false
    @io.closed_write?.should be_false
  end

  it "tries to convert the passed Object to a String using #to_str" do
    obj = mock('to_str')
    obj.should_receive(:to_str).and_return("example")
    @io.send(:initialize, obj)
    @io.string.should == "example"
  end

  it "automatically sets the mode to read-only when passed a frozen string" do
    (str = "example").freeze
    @io.send(:initialize, str)
    @io.closed_read?.should be_false
    @io.closed_write?.should be_true
  end
end

describe "StringIO#initialize when passed no arguments" do
  before :each do
    @io = StringIO.allocate
  end

  it "is private" do
    StringIO.should have_private_instance_method(:initialize)
  end

  it "sets the mode to read-write" do
    @io.send(:initialize, "example")
    @io.closed_read?.should be_false
    @io.closed_write?.should be_false
  end

  it "uses an empty String as the StringIO backend" do
    @io.send(:initialize)
    @io.string.should == ""
  end
end

describe "StringIO#initialize sets the encoding to" do
  before :each do
    @external = Encoding.default_external
    @internal = Encoding.default_internal
    Encoding.default_external = Encoding::ISO_8859_2
    Encoding.default_internal = Encoding::ISO_8859_2
  end

  after :each do
    Encoding.default_external = @external
    Encoding.default_internal = @internal
  end

  it "Encoding.default_external when passed no arguments" do
    io = StringIO.new
    io.external_encoding.should == Encoding::ISO_8859_2
    io.string.encoding.should == Encoding::ISO_8859_2
  end

  it "the same as the encoding of the String when passed a String" do
    s = ''.force_encoding(Encoding::EUC_JP)
    io = StringIO.new(s)
    io.external_encoding.should == Encoding::EUC_JP
    io.string.encoding.should == Encoding::EUC_JP
  end
end
