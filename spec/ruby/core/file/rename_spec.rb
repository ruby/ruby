require_relative '../../spec_helper'

describe "File.rename" do
  before :each do
    @old = tmp("file_rename.txt")
    @new = tmp("file_rename.new")

    rm_r @new
    touch(@old) { |f| f.puts "hello" }
  end

  after :each do
    rm_r @old, @new
  end

  it "renames a file" do
    File.should.exist?(@old)
    File.should_not.exist?(@new)
    File.rename(@old, @new)
    File.should_not.exist?(@old)
    File.should.exist?(@new)
  end

  it "raises an Errno::ENOENT if the source does not exist" do
    rm_r @old
    -> { File.rename(@old, @new) }.should.raise(Errno::ENOENT)
  end

  it "raises an ArgumentError if not passed two arguments" do
    -> { File.rename        }.should.raise(ArgumentError)
    -> { File.rename(@file) }.should.raise(ArgumentError)
  end

  it "raises a TypeError if not passed String types" do
    -> { File.rename(1, 2)  }.should.raise(TypeError)
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      utf8_old = tmp("file_rename_old_utf8_path_\u{3042}.txt")
      utf8_new = tmp("file_rename_new_utf8_path_\u{3042}.txt")
      # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
      non_utf8_old = utf8_old.encode(Encoding::Windows_31J)
      non_utf8_new = utf8_new.encode(Encoding::Windows_31J)

      begin
        touch(utf8_old)
        File.rename(non_utf8_old, non_utf8_new).should == 0
        File.should.exist?(utf8_new)
        File.should_not.exist?(utf8_old)
      ensure
        rm_r utf8_old, utf8_new
        rm_r non_utf8_old, non_utf8_new
      end
    end
  end
end
