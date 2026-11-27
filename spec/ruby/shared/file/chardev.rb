describe :file_chardev, shared: true do
  it "returns true/false depending if the named file is a char device" do
    @object.send(@method, tmp("")).should == false
  end

  it "accepts an object that has a #to_path method" do
    @object.send(@method, mock_to_path(tmp(""))).should == false
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      utf8_path = tmp("file_predicate_utf8_path_\u{3042}.txt")
      # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
      non_utf8_path = utf8_path.encode(Encoding::Windows_31J)

      begin
        touch(utf8_path)
        @object.send(@method, non_utf8_path).should == false
      ensure
        rm_r utf8_path
        rm_r non_utf8_path
      end
    end
  end
end
