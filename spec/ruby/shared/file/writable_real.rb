describe :file_writable_real, shared: true do
  before :each do
    @file = tmp('i_exist')
  end

  after :each do
    rm_r @file
  end

  it "returns true if named file is writable by the real user id of the process, otherwise false" do
    File.open(@file,'w') { @object.send(@method, @file).should == true }
  end

  it "accepts an object that has a #to_path method" do
    File.open(@file,'w') { @object.send(@method, mock_to_path(@file)).should == true }
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

  it "raises an ArgumentError if not passed one argument" do
    -> { File.writable_real?        }.should.raise(ArgumentError)
  end

  it "raises a TypeError if not passed a String type" do
    -> { @object.send(@method, 1)     }.should.raise(TypeError)
    -> { @object.send(@method, nil)   }.should.raise(TypeError)
    -> { @object.send(@method, false) }.should.raise(TypeError)
  end

  platform_is_not :windows do
    as_real_superuser do
      context "when run by a real superuser" do
        it "returns true unconditionally" do
          file = tmp('temp.txt')
          touch file

          File.chmod(0555, file)
          @object.send(@method, file).should == true

          rm_r file
        end
      end
    end
  end
end

describe :file_writable_real_missing, shared: true do
  it "returns false if the file does not exist" do
    @object.send(@method, 'fake_file').should == false
  end
end
