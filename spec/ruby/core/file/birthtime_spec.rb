require_relative '../../spec_helper'

platform_is :windows, :darwin, :freebsd, :netbsd, :linux do
  not_implemented_messages = [
    "birthtime() function is unimplemented", # unsupported OS/version
    "birthtime is unimplemented",            # unsupported filesystem
  ]

  describe "File.birthtime" do
    before :each do
      @file = __FILE__
    end

    after :each do
      @file = nil
    end

    it "returns the birth time for the named file as a Time object" do
      File.birthtime(@file)
      File.birthtime(@file).should.is_a?(Time)
    rescue NotImplementedError => e
      e.message.should.start_with?(*not_implemented_messages)
    end

    it "accepts an object that has a #to_path method" do
      File.birthtime(@file) # Avoid to failure of mock object with old Kernel and glibc
      File.birthtime(mock_to_path(@file))
    rescue NotImplementedError => e
      e.message.should.start_with?(*not_implemented_messages)
    end

    it "raises an Errno::ENOENT exception if the file is not found" do
      -> { File.birthtime('bogus') }.should.raise(Errno::ENOENT)
    rescue NotImplementedError => e
      e.message.should.start_with?(*not_implemented_messages)
    end

    platform_is :darwin do
      it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
        utf8_path = tmp("file_birthtime_utf8_path_\u{3042}.txt")
        # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
        non_utf8_path = utf8_path.encode(Encoding::Windows_31J)

        begin
          touch(utf8_path)
          File.birthtime(non_utf8_path).should.is_a?(Time)
        ensure
          rm_r utf8_path
          rm_r non_utf8_path
        end
      rescue NotImplementedError => e
        e.message.should.start_with?(*not_implemented_messages)
      end
    end

    platform_is :linux do
      guard -> { File.directory?('/proc') } do
        it "raises NotImplementedError for a filesystem that does not support birthtime" do
          # check if birthtime works on a regular file first
          begin
            File.birthtime(__FILE__)
          rescue NotImplementedError
            skip
          end

          -> { File.birthtime('/proc') }.should.raise(NotImplementedError, "birthtime is unimplemented on this filesystem")
        end
      end
    end
  end

  describe "File#birthtime" do
    before :each do
      @file = File.open(__FILE__)
    end

    after :each do
      @file.close
      @file = nil
    end

    it "returns the birth time for self" do
      @file.birthtime
      @file.birthtime.should.is_a?(Time)
    rescue NotImplementedError => e
      e.message.should.start_with?(*not_implemented_messages)
    end
  end
end
