describe :file_file, shared: true do
  before :each do
    platform_is :windows do
      @null = "NUL"
      @dir  = "C:\\"
    end

    platform_is_not :windows do
      @null = "/dev/null"
      @dir  = "/bin"
    end

    @file = tmp("test.txt")
    touch @file
  end

  after :each do
    rm_r @file
  end

  it "returns true if the named file exists and is a regular file." do
    @object.send(@method, @file).should == true
    @object.send(@method, @dir).should == false
  end

  it "accepts an object that has a #to_path method" do
    @object.send(@method, mock_to_path(@file)).should == true
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      utf8_path = tmp("file_predicate_utf8_path_\u{3042}.txt")
      # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
      non_utf8_path = utf8_path.encode(Encoding::Windows_31J)

      begin
        touch(utf8_path)
        @object.send(@method, non_utf8_path).should == true
      ensure
        rm_r utf8_path
        rm_r non_utf8_path
      end
    end
  end

  platform_is_not :windows do
    it "returns true if the null device exists and is a regular file." do
      @object.send(@method, @null).should == false # May fail on MS Windows
    end
  end

  it "raises an ArgumentError if not passed one argument" do
    -> { @object.send(@method)               }.should.raise(ArgumentError)
    -> { @object.send(@method, @null, @file) }.should.raise(ArgumentError)
  end

  it "raises a TypeError if not passed a String type" do
    -> { @object.send(@method, nil) }.should.raise(TypeError)
    -> { @object.send(@method, 1)   }.should.raise(TypeError)
  end
end
