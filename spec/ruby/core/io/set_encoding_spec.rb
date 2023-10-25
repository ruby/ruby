require_relative '../../spec_helper'

describe :io_set_encoding_write, shared: true do
  it "sets the encodings to nil when they were set previously" do
    @io = new_io @name, "#{@object}:ibm437:ibm866"
    @io.set_encoding nil, nil

    @io.external_encoding.should be_nil
    @io.internal_encoding.should be_nil
  end

  it "sets the encodings to nil when the IO is built with no explicit encoding" do
    @io = new_io @name, @object

    # Checking our assumptions first
    @io.external_encoding.should be_nil
    @io.internal_encoding.should be_nil

    @io.set_encoding nil, nil

    @io.external_encoding.should be_nil
    @io.internal_encoding.should be_nil
  end

  it "prevents the encodings from changing when Encoding defaults are changed" do
    @io = new_io @name, "#{@object}:utf-8:us-ascii"
    @io.set_encoding nil, nil

    Encoding.default_external = Encoding::IBM437
    Encoding.default_internal = Encoding::IBM866

    @io.external_encoding.should be_nil
    @io.internal_encoding.should be_nil
  end

  it "sets the encodings to the current Encoding defaults" do
    @io = new_io @name, @object

    Encoding.default_external = Encoding::IBM437
    Encoding.default_internal = Encoding::IBM866

    @io.set_encoding nil, nil

    @io.external_encoding.should == Encoding::IBM437
    @io.internal_encoding.should == Encoding::IBM866
  end
end

describe "IO#set_encoding when passed nil, nil" do
  before :each do
    @external = Encoding.default_external
    @internal = Encoding.default_internal

    # The defaults
    Encoding.default_external = Encoding::UTF_8
    Encoding.default_internal = nil

    @name = tmp('io_set_encoding.txt')
    touch(@name)
  end

  after :each do
    Encoding.default_external = @external
    Encoding.default_internal = @internal

    @io.close if @io and not @io.closed?
    rm_r @name
  end

  describe "with 'r' mode" do
    it "sets the encodings to the current Encoding defaults" do
      @io = new_io @name, "r"

      Encoding.default_external = Encoding::IBM437
      Encoding.default_internal = Encoding::IBM866

      @io.set_encoding nil, nil
      @io.external_encoding.should equal(Encoding::IBM437)
      @io.internal_encoding.should equal(Encoding::IBM866)
    end

    it "prevents the #internal_encoding from changing when Encoding.default_internal is changed" do
      @io = new_io @name, "r"
      @io.set_encoding nil, nil

      Encoding.default_internal = Encoding::IBM437

      @io.internal_encoding.should be_nil
    end

    it "allows the #external_encoding to change when Encoding.default_external is changed" do
      @io = new_io @name, "r"
      @io.set_encoding nil, nil

      Encoding.default_external = Encoding::IBM437

      @io.external_encoding.should equal(Encoding::IBM437)
    end
  end

  describe "with 'rb' mode" do
    it "returns Encoding.default_external" do
      @io = new_io @name, "rb"
      @io.external_encoding.should equal(Encoding::BINARY)

      @io.set_encoding nil, nil
      @io.external_encoding.should equal(Encoding.default_external)
    end
  end

  describe "with 'r+' mode" do
    it_behaves_like :io_set_encoding_write, nil, "r+"
  end

  describe "with 'w' mode" do
    it_behaves_like :io_set_encoding_write, nil, "w"
  end

  describe "with 'w+' mode" do
    it_behaves_like :io_set_encoding_write, nil, "w+"
  end

  describe "with 'a' mode" do
    it_behaves_like :io_set_encoding_write, nil, "a"
  end

  describe "with 'a+' mode" do
    it_behaves_like :io_set_encoding_write, nil, "a+"
  end

  describe "with standard IOs" do
    it "correctly resets them" do
      STDOUT.external_encoding.should == nil
      STDOUT.internal_encoding.should == nil

      begin
        STDOUT.set_encoding(Encoding::US_ASCII, Encoding::ISO_8859_1)
      ensure
        STDOUT.set_encoding(nil, nil)
      end

      STDOUT.external_encoding.should == nil
      STDOUT.internal_encoding.should == nil
    end
  end
end

describe "IO#set_encoding" do
  before :each do
    @name = tmp('io_set_encoding.txt')
    touch(@name)
    @io = new_io @name
  end

  after :each do
    @io.close unless @io.closed?
    rm_r @name
  end

  it "returns self" do
    @io.set_encoding(Encoding::UTF_8).should equal(@io)
  end

  it "sets the external encoding when passed an Encoding argument" do
    @io.set_encoding(Encoding::UTF_8)
    @io.external_encoding.should == Encoding::UTF_8
    @io.internal_encoding.should be_nil
  end

  it "sets the external and internal encoding when passed two Encoding arguments" do
    @io.set_encoding(Encoding::UTF_8, Encoding::UTF_16BE)
    @io.external_encoding.should == Encoding::UTF_8
    @io.internal_encoding.should == Encoding::UTF_16BE
  end

  it "sets the external encoding when passed the name of an Encoding" do
    @io.set_encoding("utf-8")
    @io.external_encoding.should == Encoding::UTF_8
    @io.internal_encoding.should be_nil
  end

  it "ignores the internal encoding if the same as external when passed Encoding objects" do
    @io.set_encoding(Encoding::UTF_8, Encoding::UTF_8)
    @io.external_encoding.should == Encoding::UTF_8
    @io.internal_encoding.should be_nil
  end

  it "ignores the internal encoding if the same as external when passed encoding names separated by ':'" do
    @io.set_encoding("utf-8:utf-8")
    @io.external_encoding.should == Encoding::UTF_8
    @io.internal_encoding.should be_nil
  end

  it "sets the external and internal encoding when passed the names of Encodings separated by ':'" do
    @io.set_encoding("utf-8:utf-16be")
    @io.external_encoding.should == Encoding::UTF_8
    @io.internal_encoding.should == Encoding::UTF_16BE
  end

  it "sets the external and internal encoding when passed two String arguments" do
    @io.set_encoding("utf-8", "utf-16be")
    @io.external_encoding.should == Encoding::UTF_8
    @io.internal_encoding.should == Encoding::UTF_16BE
  end

  it "calls #to_str to convert an abject to a String" do
    obj = mock("io_set_encoding")
    obj.should_receive(:to_str).and_return("utf-8:utf-16be")
    @io.set_encoding(obj)
    @io.external_encoding.should == Encoding::UTF_8
    @io.internal_encoding.should == Encoding::UTF_16BE
  end

  it "calls #to_str to convert the second argument to a String" do
    obj = mock("io_set_encoding")
    obj.should_receive(:to_str).at_least(1).times.and_return("utf-16be")
    @io.set_encoding(Encoding::UTF_8, obj)
    @io.external_encoding.should == Encoding::UTF_8
    @io.internal_encoding.should == Encoding::UTF_16BE
  end

  it "saves encoding options passed as a hash in the last argument" do
    File.write(@name, "\xff")
    io = File.open(@name)
    io.set_encoding(Encoding::EUC_JP, Encoding::SHIFT_JIS, invalid: :replace, replace: ".")
    io.read.should == "."
  ensure
    io.close
  end

  it "raises ArgumentError when no arguments are given" do
    -> { @io.set_encoding() }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError when too many arguments are given" do
    -> { @io.set_encoding(1, 2, 3) }.should raise_error(ArgumentError)
  end
end
