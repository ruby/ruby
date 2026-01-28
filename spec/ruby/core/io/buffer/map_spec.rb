require_relative '../../../spec_helper'

describe "IO::Buffer.map" do
  before :all do
    @big_file_name = tmp("big_file")
    # Usually 4 kibibytes + 16 bytes
    File.write(@big_file_name, "12345678" * (IO::Buffer::PAGE_SIZE / 8 + 2))
  end

  after :all do
    File.delete(@big_file_name)
  end

  def open_fixture
    File.open("#{__dir__}/../fixtures/read_text.txt", "r+")
  end

  def open_big_file_fixture
    File.open(@big_file_name, "r+")
  end

  after :each do
    @buffer&.free
    @buffer = nil
    @file&.close
    @file = nil
  end

  it "creates a new buffer mapped from a file" do
    @file = open_fixture
    @buffer = IO::Buffer.map(@file)

    @buffer.size.should == 9
    @buffer.get_string.should == "abcâdef\n".b
  end

  it "allows to close the file after creating buffer, retaining mapping" do
    file = open_fixture
    @buffer = IO::Buffer.map(file)
    file.close

    @buffer.get_string.should == "abcâdef\n".b
  end

  it "creates a mapped, external, shared buffer" do
    @file = open_fixture
    @buffer = IO::Buffer.map(@file)

    @buffer.should_not.internal?
    @buffer.should.mapped?
    @buffer.should.external?

    @buffer.should_not.empty?
    @buffer.should_not.null?

    @buffer.should.shared?
    @buffer.should_not.private?
    @buffer.should_not.readonly?

    @buffer.should_not.locked?
    @buffer.should.valid?
  end

  platform_is_not :windows do
    it "is shareable across processes" do
      file_name = tmp("shared_buffer")
      @file = File.open(file_name, "w+")
      @file << "I'm private"
      @file.rewind
      @buffer = IO::Buffer.map(@file)

      IO.popen("-") do |child_pipe|
        if child_pipe
          # Synchronize on child's output.
          child_pipe.readlines.first.chomp.should == @buffer.to_s
          @buffer.get_string.should == "I'm shared!"

          @file.read.should == "I'm shared!"
        else
          @buffer.set_string("I'm shared!")
          puts @buffer
        end
      ensure
        child_pipe&.close
      end
    ensure
      File.unlink(file_name)
    end
  end

  context "with an empty file" do
    ruby_version_is ""..."4.0" do
      it "raises a SystemCallError" do
        @file = File.open("#{__dir__}/../fixtures/empty.txt", "r+")
        -> { IO::Buffer.map(@file) }.should raise_error(SystemCallError)
      end
    end

    ruby_version_is "4.0" do
      it "raises ArgumentError" do
        @file = File.open("#{__dir__}/../fixtures/empty.txt", "r+")
        -> { IO::Buffer.map(@file) }.should raise_error(ArgumentError, "Invalid negative or zero file size!")
      end
    end
  end

  context "with a file opened only for reading" do
    it "raises a SystemCallError if no flags are used" do
      @file = File.open("#{__dir__}/../fixtures/read_text.txt", "r")
      -> { IO::Buffer.map(@file) }.should raise_error(SystemCallError)
    end
  end

  context "with size argument" do
    it "limits the buffer to the specified size in bytes, starting from the start of the file" do
      @file = open_fixture
      @buffer = IO::Buffer.map(@file, 4)

      @buffer.size.should == 4
      @buffer.get_string.should == "abc\xC3".b
    end

    it "maps the whole file if size is nil" do
      @file = open_fixture
      @buffer = IO::Buffer.map(@file, nil)

      @buffer.size.should == 9
    end

    context "if size is 0" do
      ruby_version_is ""..."4.0" do
        platform_is_not :windows do
          it "raises a SystemCallError" do
            @file = open_fixture
            -> { IO::Buffer.map(@file, 0) }.should raise_error(SystemCallError)
          end
        end
      end

      ruby_version_is "4.0" do
        it "raises ArgumentError" do
          @file = open_fixture
          -> { IO::Buffer.map(@file, 0) }.should raise_error(ArgumentError, "Size can't be zero!")
        end
      end
    end

    it "raises TypeError if size is not an Integer or nil" do
      @file = open_fixture
      -> { IO::Buffer.map(@file, "10") }.should raise_error(TypeError, "not an Integer")
      -> { IO::Buffer.map(@file, 10.0) }.should raise_error(TypeError, "not an Integer")
    end

    it "raises ArgumentError if size is negative" do
      @file = open_fixture
      -> { IO::Buffer.map(@file, -1) }.should raise_error(ArgumentError, "Size can't be negative!")
    end

    ruby_version_is ""..."4.0" do
      # May or may not cause a crash on access.
      it "is undefined behavior if size is larger than file size"
    end

    ruby_version_is "4.0" do
      it "raises ArgumentError if size is larger than file size" do
        @file = open_fixture
        -> { IO::Buffer.map(@file, 8192) }.should raise_error(ArgumentError, "Size can't be larger than file size!")
      end
    end
  end

  context "with size and offset arguments" do
    # Neither Windows nor macOS have clear, stable behavior with non-zero offset.
    # https://bugs.ruby-lang.org/issues/21700
    platform_is :linux do
      context "if offset is an allowed value for system call" do
        it "maps the span specified by size starting from the offset" do
          @file = open_big_file_fixture
          @buffer = IO::Buffer.map(@file, 14, IO::Buffer::PAGE_SIZE)

          @buffer.size.should == 14
          @buffer.get_string(0, 14).should == "12345678123456"
        end

        context "if size is nil" do
          ruby_version_is ""..."4.0" do
            it "maps the rest of the file" do
              @file = open_big_file_fixture
              @buffer = IO::Buffer.map(@file, nil, IO::Buffer::PAGE_SIZE)

              @buffer.get_string(0, 1).should == "1"
            end

            it "incorrectly sets buffer's size to file's full size" do
              @file = open_big_file_fixture
              @buffer = IO::Buffer.map(@file, nil, IO::Buffer::PAGE_SIZE)

              @buffer.size.should == @file.size
            end
          end

          ruby_version_is "4.0" do
            it "maps the rest of the file" do
              @file = open_big_file_fixture
              @buffer = IO::Buffer.map(@file, nil, IO::Buffer::PAGE_SIZE)

              @buffer.get_string(0, 1).should == "1"
            end

            it "sets buffer's size to file's remaining size" do
              @file = open_big_file_fixture
              @buffer = IO::Buffer.map(@file, nil, IO::Buffer::PAGE_SIZE)

              @buffer.size.should == (@file.size - IO::Buffer::PAGE_SIZE)
            end
          end
        end
      end
    end

    it "maps the file from the start if offset is 0" do
      @file = open_fixture
      @buffer = IO::Buffer.map(@file, 4, 0)

      @buffer.size.should == 4
      @buffer.get_string.should == "abc\xC3".b
    end

    ruby_version_is ""..."4.0" do
      # May or may not cause a crash on access.
      it "is undefined behavior if offset+size is larger than file size"
    end

    ruby_version_is "4.0" do
      it "raises ArgumentError if offset+size is larger than file size" do
        @file = open_big_file_fixture
        -> { IO::Buffer.map(@file, 17, IO::Buffer::PAGE_SIZE) }.should raise_error(ArgumentError, "Offset too large!")
      ensure
        # Windows requires the file to be closed before deletion.
        @file.close unless @file.closed?
      end
    end

    it "raises TypeError if offset is not convertible to Integer" do
      @file = open_fixture
      -> { IO::Buffer.map(@file, 4, "4096") }.should raise_error(TypeError, /no implicit conversion/)
      -> { IO::Buffer.map(@file, 4, nil) }.should raise_error(TypeError, /no implicit conversion/)
    end

    it "raises a SystemCallError if offset is not an allowed value" do
      @file = open_fixture
      -> { IO::Buffer.map(@file, 4, 3) }.should raise_error(SystemCallError)
    end

    ruby_version_is ""..."4.0" do
      it "raises a SystemCallError if offset is negative" do
        @file = open_fixture
        -> { IO::Buffer.map(@file, 4, -1) }.should raise_error(SystemCallError)
      end
    end

    ruby_version_is "4.0" do
      it "raises ArgumentError if offset is negative" do
        @file = open_fixture
        -> { IO::Buffer.map(@file, 4, -1) }.should raise_error(ArgumentError, "Offset can't be negative!")
      end
    end
  end

  context "with flags argument" do
    context "when READONLY flag is specified" do
      it "sets readonly flag on the buffer, allowing only reads" do
        @file = open_fixture
        @buffer = IO::Buffer.map(@file, nil, 0, IO::Buffer::READONLY)

        @buffer.should.readonly?

        @buffer.get_string.should == "abc\xC3\xA2def\n".b
      end

      it "allows mapping read-only files" do
        @file = File.open("#{__dir__}/../fixtures/read_text.txt", "r")
        @buffer = IO::Buffer.map(@file, nil, 0, IO::Buffer::READONLY)

        @buffer.should.readonly?

        @buffer.get_string.should == "abc\xC3\xA2def\n".b
      end

      it "causes IO::Buffer::AccessError on write" do
        @file = open_fixture
        @buffer = IO::Buffer.map(@file, nil, 0, IO::Buffer::READONLY)

        -> { @buffer.set_string("test") }.should raise_error(IO::Buffer::AccessError, "Buffer is not writable!")
      end
    end

    context "when PRIVATE is specified" do
      it "sets private flag on the buffer, making it freely modifiable" do
        @file = open_fixture
        @buffer = IO::Buffer.map(@file, nil, 0, IO::Buffer::PRIVATE)

        @buffer.should.private?
        @buffer.should_not.shared?
        @buffer.should_not.external?

        @buffer.get_string.should == "abc\xC3\xA2def\n".b
        @buffer.set_string("test12345")
        @buffer.get_string.should == "test12345".b

        @file.read.should == "abcâdef\n"
      end

      it "allows mapping read-only files and modifying the buffer" do
        @file = File.open("#{__dir__}/../fixtures/read_text.txt", "r")
        @buffer = IO::Buffer.map(@file, nil, 0, IO::Buffer::PRIVATE)

        @buffer.should.private?
        @buffer.should_not.shared?
        @buffer.should_not.external?

        @buffer.get_string.should == "abc\xC3\xA2def\n".b
        @buffer.set_string("test12345")
        @buffer.get_string.should == "test12345".b

        @file.read.should == "abcâdef\n"
      end

      platform_is_not :windows do
        it "is not shared across processes" do
          file_name = tmp("shared_buffer")
          @file = File.open(file_name, "w+")
          @file << "I'm private"
          @file.rewind
          @buffer = IO::Buffer.map(@file, nil, 0, IO::Buffer::PRIVATE)

          IO.popen("-") do |child_pipe|
            if child_pipe
              # Synchronize on child's output.
              child_pipe.readlines.first.chomp.should == @buffer.to_s
              @buffer.get_string.should == "I'm private"

              @file.read.should == "I'm private"
            else
              @buffer.set_string("I'm shared!")
              puts @buffer
            end
          ensure
            child_pipe&.close
          end
        ensure
          File.unlink(file_name)
        end
      end
    end
  end
end
