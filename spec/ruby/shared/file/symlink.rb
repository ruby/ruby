describe :file_symlink, shared: true do
  before :each do
    @file = tmp("test.txt")
    @link = tmp("test.lnk")

    rm_r @link
    touch @file
  end

  after :each do
    rm_r @link, @file
  end

  platform_is_not :windows do
    it "returns true if the file is a link" do
      File.symlink(@file, @link)
      @object.send(@method, @link).should == true
    end

    it "accepts an object that has a #to_path method" do
      File.symlink(@file, @link)
      @object.send(@method, mock_to_path(@link)).should == true
    end
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      utf8_path = tmp("file_predicate_utf8_path_\u{3042}.txt")
      # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
      non_utf8_path = utf8_path.encode(Encoding::Windows_31J)
      File.symlink(@file, utf8_path)

      begin
        @object.send(@method, non_utf8_path).should == true
      ensure
        rm_r utf8_path
        rm_r non_utf8_path
      end
    end
  end
end

describe :file_symlink_nonexistent, shared: true do
  before :each do
    @file = tmp("test.txt")
    @link = tmp("test.lnk")

    rm_r @link
    touch @file
  end

  after :each do
    rm_r @link
    rm_r @file
  end

  platform_is_not :windows do
    it "returns false if the file does not exist" do
      @object.send(@method, "non_existent_link").should == false
    end
  end
end
