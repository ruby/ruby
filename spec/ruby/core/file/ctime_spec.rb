require_relative '../../spec_helper'

describe "File.ctime" do
  before :each do
    @file = __FILE__
  end

  after :each do
    @file = nil
  end

  it "returns the change time for the named file (the time at which directory information about the file was changed, not the file itself)." do
    File.ctime(@file)
    File.ctime(@file).should.is_a?(Time)
  end

  platform_is :linux, :windows do
    it "returns the change time for the named file (the time at which directory information about the file was changed, not the file itself) with microseconds." do
      supports_subseconds = Integer(`stat -c%z #{__FILE__}`[/\.(\d{1,6})/, 1], 10)
      if supports_subseconds != 0
        File.ctime(__FILE__).usec.should > 0
      else
        File.ctime(__FILE__).usec.should == 0
      end
    rescue Errno::ENOENT => e
      # Windows don't have stat command.
      skip e.message
    end
  end

  it "accepts an object that has a #to_path method" do
    File.ctime(mock_to_path(@file))
  end

  it "raises an Errno::ENOENT exception if the file is not found" do
    -> { File.ctime('bogus') }.should.raise(Errno::ENOENT)
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      utf8_path = tmp("file_ctime_utf8_path_\u{3042}.txt")
      # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
      non_utf8_path = utf8_path.encode(Encoding::Windows_31J)

      begin
        touch(utf8_path)
        File.ctime(non_utf8_path).should.is_a?(Time)
      ensure
        rm_r utf8_path
        rm_r non_utf8_path
      end
    end
  end
end

describe "File#ctime" do
  before :each do
    @file = File.open(__FILE__)
  end

  after :each do
    @file.close
    @file = nil
  end

  it "returns the change time for the named file (the time at which directory information about the file was changed, not the file itself)." do
    @file.ctime
    @file.ctime.should.is_a?(Time)
  end
end
