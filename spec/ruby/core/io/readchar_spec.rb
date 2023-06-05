require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe :io_readchar_internal_encoding, shared: true do
  it "returns a transcoded String" do
    @io.readchar.should == "あ"
  end

  it "sets the String encoding to the internal encoding" do
    @io.readchar.encoding.should equal(Encoding::UTF_8)
  end
end

describe "IO#readchar" do
  before :each do
    @io = IOSpecs.io_fixture "lines.txt"
  end

  after :each do
    @io.close unless @io.closed?
  end

  it "returns the next string from the stream" do
    @io.readchar.should == 'V'
    @io.readchar.should == 'o'
    @io.readchar.should == 'i'
    # read the rest of line
    @io.readline.should == "ci la ligne une.\n"
    @io.readchar.should == 'Q'
  end

  it "raises an EOFError when invoked at the end of the stream" do
    @io.read
    -> { @io.readchar }.should raise_error(EOFError)
  end

  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.readchar }.should raise_error(IOError)
  end
end

describe "IO#readchar with internal encoding" do
  after :each do
    @io.close if @io
  end

  describe "not specified" do
    before :each do
      @io = IOSpecs.io_fixture "read_euc_jp.txt", "r:euc-jp"
    end

    it "does not transcode the String" do
      @io.readchar.should == ("あ").encode(Encoding::EUC_JP)
    end

    it "sets the String encoding to the external encoding" do
      @io.readchar.encoding.should equal(Encoding::EUC_JP)
    end
  end

  describe "specified by open mode" do
    before :each do
      @io = IOSpecs.io_fixture "read_euc_jp.txt", "r:euc-jp:utf-8"
    end

    it_behaves_like :io_readchar_internal_encoding, nil
  end

  describe "specified by mode: option" do
    before :each do
      @io = IOSpecs.io_fixture "read_euc_jp.txt", mode: "r:euc-jp:utf-8"
    end

    it_behaves_like :io_readchar_internal_encoding, nil
  end

  describe "specified by internal_encoding: option" do
    before :each do
      options = { mode: "r",
                  internal_encoding: "utf-8",
                  external_encoding: "euc-jp" }
      @io = IOSpecs.io_fixture "read_euc_jp.txt", options
    end

    it_behaves_like :io_readchar_internal_encoding, nil
  end

  describe "specified by encoding: option" do
    before :each do
      options = { mode: "r", encoding: "euc-jp:utf-8" }
      @io = IOSpecs.io_fixture "read_euc_jp.txt", options
    end

    it_behaves_like :io_readchar_internal_encoding, nil
  end
end

describe "IO#readchar" do
  before :each do
    @io = IOSpecs.io_fixture "empty.txt"
  end

  after :each do
    @io.close unless @io.closed?
  end

  it "raises EOFError on empty stream" do
    -> { @io.readchar }.should raise_error(EOFError)
  end
end
