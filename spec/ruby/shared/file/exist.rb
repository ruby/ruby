describe :file_exist, shared: true do
  it "returns true if the file exist" do
    @object.send(@method, __FILE__).should == true
    @object.send(@method, 'a_fake_file').should == false
  end

  it "raises an ArgumentError if not passed one argument" do
    -> { @object.send(@method) }.should.raise(ArgumentError)
    -> { @object.send(@method, __FILE__, __FILE__) }.should.raise(ArgumentError)
  end

  it "raises a TypeError if not passed a String type" do
    -> { @object.send(@method, nil) }.should.raise(TypeError)
  end

  it "accepts an object that has a #to_path method" do
    @object.send(@method, mock_to_path(__FILE__)).should == true
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      utf8_path = tmp("file_predicate_utf8_path_\u{3042}.txt")
      # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
      non_utf8_path = utf8_path.encode(Encoding::Windows_31J)

      begin
        @object.send(@method, non_utf8_path).should == false

        touch(utf8_path)
        @object.send(@method, non_utf8_path).should == true
      ensure
        rm_r utf8_path
        rm_r non_utf8_path
      end
    end
  end
end
