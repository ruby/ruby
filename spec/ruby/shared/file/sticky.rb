describe :file_sticky, shared: true do
  before :each do
    @dir = tmp('sticky_dir')
    Dir.rmdir(@dir) if File.exist?(@dir)
  end

  after :each do
    Dir.rmdir(@dir) if File.exist?(@dir)
  end

  platform_is_not :windows, :darwin, :freebsd, :netbsd, :openbsd, :aix do
    it "returns true if the named file has the sticky bit, otherwise false" do
      Dir.mkdir @dir, 01755

      @object.send(@method, @dir).should == true
      @object.send(@method, '/').should == false
    end
  end

  it "accepts an object that has a #to_path method"

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      utf8_path = tmp("file_predicate_utf8_path_\u{3042}.txt")
      # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
      non_utf8_path = utf8_path.encode(Encoding::Windows_31J)

      begin
        touch(utf8_path)
        @object.send(@method, non_utf8_path).should == false

        system "chmod +t #{utf8_path}"
        @object.send(@method, non_utf8_path).should == true
      ensure
        rm_r utf8_path
        rm_r non_utf8_path
      end
    end
  end
end

describe :file_sticky_missing, shared: true do
  platform_is_not :windows do
    it "returns false if the file dies not exist" do
      @object.send(@method, 'fake_file').should == false
    end
  end
end
