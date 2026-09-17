require_relative '../../spec_helper'

describe "File.readlink" do
  # symlink/readlink are not supported on Windows
  platform_is_not :windows do
    describe "with absolute paths" do
      before :each do
        @file = tmp('file_readlink.txt')
        @link = tmp('file_readlink.lnk')

        File.symlink(@file, @link)
      end

      after :each do
        rm_r @file, @link
      end

      it "returns the name of the file referenced by the given link" do
        touch @file
        File.readlink(@link).should == @file
      end

      it "returns the name of the file referenced by the given link when the file does not exist" do
        File.readlink(@link).should == @file
      end

      it "raises an Errno::ENOENT if there is no such file" do
        # TODO: missing_file
        -> { File.readlink("/this/surely/does/not/exist") }.should.raise(Errno::ENOENT)
      end

      it "raises an Errno::EINVAL if called with a normal file" do
        touch @file
        -> { File.readlink(@file) }.should.raise(Errno::EINVAL)
      end
    end

    describe "with paths containing unicode characters" do
      before :each do
        @file = tmp('tàrget.txt')
        @link = tmp('lïnk.lnk')
        File.symlink(@file, @link)
      end

      after :each do
        rm_r @file, @link
      end

      it "returns the name of the file referenced by the given link" do
        touch @file
        result = File.readlink(@link)
        result.encoding.should.equal? Encoding.find('filesystem')
        result.should == @file.dup.force_encoding(Encoding.find('filesystem'))
      end
    end

    describe "when changing the working directory" do
      before :each do
        @cwd = Dir.pwd
        @tmpdir = tmp("/readlink")
        Dir.mkdir @tmpdir
        Dir.chdir @tmpdir

        @link = 'readlink_link'
        @file = 'readlink_file'

        File.symlink(@file, @link)
      end

      after :each do
        rm_r @file, @link
        Dir.chdir @cwd
        Dir.rmdir @tmpdir
      end

      it "returns the name of the file referenced by the given link" do
        touch @file
        File.readlink(@link).should == @file
      end

      it "returns the name of the file referenced by the given link when the file does not exist" do
        File.readlink(@link).should == @file
      end
    end

    platform_is :darwin do
      it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
        utf8_file = tmp("file_readlink_file_utf8_path_\u{3042}.txt")
        utf8_link = tmp("file_readlink_link_utf8_path_\u{3042}.txt")
        # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
        non_utf8_file = utf8_file.encode(Encoding::Windows_31J)
        non_utf8_link = utf8_link.encode(Encoding::Windows_31J)

        begin
          File.symlink(utf8_file, utf8_link)
          File.readlink(non_utf8_link).should == utf8_file
        ensure
          rm_r utf8_file, utf8_link
          rm_r non_utf8_file, non_utf8_link
        end
      end
    end
  end
end
