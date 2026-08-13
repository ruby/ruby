describe :file_stat, shared: true do
  before :each do
    @file = tmp('i_exist')
    touch(@file)
  end

  after :each do
    rm_r @file
  end

  it "returns a File::Stat object if the given file exists" do
    st = File.send(@method, @file)
    st.should.instance_of?(File::Stat)
  end

  it "returns a File::Stat object when called on an instance of File" do
    File.open(@file) do |f|
      st = f.send(@method)
      st.should.instance_of?(File::Stat)
    end
  end

  it "accepts an object that has a #to_path method" do
    File.send(@method, mock_to_path(@file))
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      utf8_path = tmp("file_lstat_utf8_path_\u{3042}.txt")
      # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
      non_utf8_path = utf8_path.encode(Encoding::Windows_31J)

      begin
        touch(utf8_path)
        File.send(@method, non_utf8_path).should.is_a?(File::Stat)
      ensure
        rm_r utf8_path
        rm_r non_utf8_path
      end
    end
  end

  it "raises an Errno::ENOENT if the file does not exist" do
    -> {
      File.send(@method, "fake_file")
    }.should.raise(Errno::ENOENT)
  end
end
