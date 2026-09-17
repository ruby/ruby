require_relative '../../spec_helper'

describe "File.lchmod" do
  platform_is_not :linux, :windows, :openbsd, :aix do
    before :each do
      @fname = tmp('file_chmod_test')
      @lname = @fname + '.lnk'

      touch(@fname) { |f| f.write "rubinius" }

      rm_r @lname
      File.symlink @fname, @lname
    end

    after :each do
      rm_r @lname, @fname
    end

    it "changes the file mode of the link and not of the file" do
      File.chmod(0222, @lname).should == 1
      File.lchmod(0755, @lname).should == 1

      File.lstat(@lname).should.executable?
      File.lstat(@lname).should.readable?
      File.lstat(@lname).should.writable?

      File.stat(@lname).should_not.executable?
      File.stat(@lname).should_not.readable?
      File.stat(@lname).should.writable?
    end

    platform_is :darwin do
      it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
        utf8_path = tmp("file_lchmod_utf8_path_\u{3042}.txt")
        # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
        non_utf8_path = utf8_path.encode(Encoding::Windows_31J)

        begin
          touch(utf8_path)
          File.lchmod(0755, non_utf8_path).should == 1
        ensure
          rm_r utf8_path
          rm_r non_utf8_path
        end
      end
    end
  end
end
