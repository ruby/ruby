# encoding: utf-8
require_relative '../fixtures/classes'

describe :io_write, shared: true do
  before :each do
    @filename = tmp("IO_syswrite_file") + $$.to_s
    File.open(@filename, "w") do |file|
      file.send(@method, "012345678901234567890123456789")
    end
    @file = File.open(@filename, "r+")
    @readonly_file = File.open(@filename)
  end

  after :each do
    @readonly_file.close if @readonly_file
    @file.close if @file
    rm_r @filename
  end

  it "coerces the argument to a string using to_s" do
    (obj = mock('test')).should_receive(:to_s).and_return('a string')
    @file.send(@method, obj)
  end

  it "checks if the file is writable if writing more than zero bytes" do
    -> { @readonly_file.send(@method, "abcde") }.should raise_error(IOError)
  end

  it "returns the number of bytes written" do
    written = @file.send(@method, "abcde")
    written.should == 5
  end

  it "invokes to_s on non-String argument" do
    data = "abcdefgh9876"
    (obj = mock(data)).should_receive(:to_s).and_return(data)
    @file.send(@method, obj)
    @file.seek(0)
    @file.read(data.size).should == data
  end

  it "writes all of the string's bytes without buffering if mode is sync" do
    @file.sync = true
    written = @file.send(@method, "abcde")
    written.should == 5
    File.open(@filename) do |file|
      file.read(10).should == "abcde56789"
    end
  end

  it "does not warn if called after IO#read" do
    @file.read(5)
    -> { @file.send(@method, "fghij") }.should_not complain
  end

  it "writes to the current position after IO#read" do
    @file.read(5)
    @file.send(@method, "abcd")
    @file.rewind
    @file.read.should == "01234abcd901234567890123456789"
  end

  it "advances the file position by the count of given bytes" do
    @file.send(@method, "abcde")
    @file.read(10).should == "5678901234"
  end

  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.send(@method, "hello") }.should raise_error(IOError)
  end

  describe "on a pipe" do
    before :each do
      @r, @w = IO.pipe
    end

    after :each do
      @r.close
      @w.close
    end

    it "writes the given String to the pipe" do
      @w.send(@method, "foo")
      @w.close
      @r.read.should == "foo"
    end

    # [ruby-core:90895] RJIT worker may leave fd open in a forked child.
    # For instance, RJIT creates a worker before @r.close with fork(), @r.close happens,
    # and the RJIT worker keeps the pipe open until the worker execve().
    # TODO: consider acquiring GVL from RJIT worker.
    guard_not -> { defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled? } do
      it "raises Errno::EPIPE if the read end is closed and does not die from SIGPIPE" do
        @r.close
        -> { @w.send(@method, "foo") }.should raise_error(Errno::EPIPE, /Broken pipe/)
      end
    end
  end
end

describe :io_write_transcode, shared: true do
  before :each do
    @transcode_filename = tmp("io_write_transcode")
  end

  after :each do
    rm_r @transcode_filename
  end

  it "transcodes the given string when the external encoding is set and neither is BINARY" do
    utf8_str = "hello"

    File.open(@transcode_filename, "w", external_encoding: Encoding::UTF_16BE) do |file|
      file.external_encoding.should == Encoding::UTF_16BE
      file.send(@method, utf8_str)
    end

    result = File.binread(@transcode_filename)
    expected = [0, 104, 0, 101, 0, 108, 0, 108, 0, 111] # UTF-16BE bytes for "hello"

    result.bytes.should == expected
  end

  it "transcodes the given string when the external encoding is set and the string encoding is BINARY" do
    str = "été".b

    File.open(@transcode_filename, "w", external_encoding: Encoding::UTF_16BE) do |file|
      file.external_encoding.should == Encoding::UTF_16BE
      -> { file.send(@method, str) }.should raise_error(Encoding::UndefinedConversionError)
    end
  end
end

describe :io_write_no_transcode, shared: true do
  before :each do
    @transcode_filename = tmp("io_write_no_transcode")
  end

  after :each do
    rm_r @transcode_filename
  end

  it "does not transcode the given string even when the external encoding is set" do
    utf8_str = "hello"

    File.open(@transcode_filename, "w", external_encoding: Encoding::UTF_16BE) do |file|
      file.external_encoding.should == Encoding::UTF_16BE
      file.send(@method, utf8_str)
    end

    result = File.binread(@transcode_filename)
    result.bytes.should == utf8_str.bytes
  end
end
