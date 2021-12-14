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

  it "does not modify the passed argument" do
    File.open(@filename, "w") do |f|
      f.set_encoding(Encoding::IBM437)
      # A character whose codepoint differs between UTF-8 and IBM437
      f.write "ƒ".freeze
    end

    File.binread(@filename).bytes.should == [159]
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

    # [ruby-core:90895] MJIT worker may leave fd open in a forked child.
    # For instance, MJIT creates a worker before @r.close with fork(), @r.close happens,
    # and the MJIT worker keeps the pipe open until the worker execve().
    # TODO: consider acquiring GVL from MJIT worker.
    guard_not -> { defined?(RubyVM::MJIT) && RubyVM::MJIT.enabled? } do
      it "raises Errno::EPIPE if the read end is closed and does not die from SIGPIPE" do
        @r.close
        -> { @w.send(@method, "foo") }.should raise_error(Errno::EPIPE, /Broken pipe/)
      end
    end
  end
end
