describe :file_directory, shared: true do
  before :each do
    @dir = tmp("file_directory")
    @file = tmp("file_directory.txt")

    mkdir_p @dir
    touch @file
  end

  after :each do
    rm_r @dir, @file
  end

  it "returns true if the argument is a directory" do
    @object.send(@method, @dir).should == true
  end

  it "returns false if the argument is not a directory" do
    @object.send(@method, @file).should == false
  end

  it "accepts an object that has a #to_path method" do
    @object.send(@method, mock_to_path(@dir)).should == true
  end

  it "raises a TypeError when passed an Integer" do
    -> { @object.send(@method, 1) }.should.raise(TypeError)
    -> { @object.send(@method, bignum_value) }.should.raise(TypeError)
  end

  it "raises a TypeError when passed nil" do
    -> { @object.send(@method, nil) }.should.raise(TypeError)
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      utf8_path = tmp("file_predicate_utf8_path_\u{3042}.txt")
      # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
      non_utf8_path = utf8_path.encode(Encoding::Windows_31J)

      begin
        touch(utf8_path)
        @object.send(@method, non_utf8_path).should == false

        rm_r utf8_path
        rm_r non_utf8_path

        mkdir_p utf8_path
        @object.send(@method, non_utf8_path).should == true
      ensure
        rm_r utf8_path
        rm_r non_utf8_path
      end
    end
  end
end

describe :file_directory_io, shared: true do
  before :each do
    @dir = tmp("file_directory_io")
    @file = tmp("file_directory_io.txt")

    mkdir_p @dir
    touch @file
  end

  after :each do
    rm_r @dir, @file
  end

  it "returns false if the argument is an IO that's not a directory" do
    @object.send(@method, STDIN).should == false
  end

  platform_is_not :windows do
    it "returns true if the argument is an IO that is a directory" do
      File.open(@dir, "r") do |f|
        @object.send(@method, f).should == true
      end
    end
  end

  it "calls #to_io to convert a non-IO object" do
    io = mock('FileDirectoryIO')
    io.should_receive(:to_io).and_return(STDIN)
    @object.send(@method, io).should == false
  end
end
