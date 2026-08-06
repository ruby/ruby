require_relative '../../spec_helper'

describe "File.link" do
  before :each do
    @file = tmp("file_link.txt")
    @link = tmp("file_link.lnk")

    rm_r @link
    touch @file
  end

  after :each do
    rm_r @link, @file
  end

  platform_is_not :windows, :android do
    it "link a file with another" do
      File.link(@file, @link).should == 0
      File.should.exist?(@link)
      File.identical?(@file, @link).should == true
    end

    it "raises an Errno::EEXIST if the target already exists" do
      File.link(@file, @link)
      -> { File.link(@file, @link) }.should.raise(Errno::EEXIST)
    end

    it "raises an ArgumentError if not passed two arguments" do
      -> { File.link                      }.should.raise(ArgumentError)
      -> { File.link(@file)               }.should.raise(ArgumentError)
      -> { File.link(@file, @link, @file) }.should.raise(ArgumentError)
    end

    it "raises a TypeError if not passed String types" do
      -> { File.link(@file, nil) }.should.raise(TypeError)
      -> { File.link(@file, 1)   }.should.raise(TypeError)
    end

    platform_is :darwin do
      it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
        utf8_file = tmp("file_link_file_utf8_path_\u{3042}.txt")
        utf8_link = tmp("file_link_link_utf8_path_\u{3042}.txt")
        # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
        non_utf8_file = utf8_file.encode(Encoding::Windows_31J)
        non_utf8_link = utf8_link.encode(Encoding::Windows_31J)

        begin
          touch(utf8_file)
          File.link(non_utf8_file, non_utf8_link).should == 0
          File.should.exist?(utf8_link)
        ensure
          rm_r utf8_file, utf8_link
          rm_r non_utf8_file, non_utf8_link
        end
      end
    end
  end
end
