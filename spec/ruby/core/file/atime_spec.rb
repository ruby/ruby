require_relative '../../spec_helper'

describe "File.atime" do
  before :each do
    @file = tmp('test.txt')
    touch @file
  end

  after :each do
    rm_r @file
  end

  it "returns the last access time for the named file as a Time object" do
    File.atime(@file)
    File.atime(@file).should.is_a?(Time)
  end

  platform_is :linux, :windows do
    unless ENV.key?('TRAVIS') # https://bugs.ruby-lang.org/issues/17926
      ## NOTE also that some Linux systems disable atime (e.g. via mount params) for better filesystem speed.
      it "returns the last access time for the named file with microseconds" do
        supports_subseconds = Integer(`stat -c%x #{__FILE__}`[/\.(\d{1,6})/, 1], 10)
        if supports_subseconds != 0
          expected_time = Time.at(Time.now.to_i + 0.123456)
          File.utime expected_time, 0, @file
          File.atime(@file).usec.should == expected_time.usec
        else
          File.atime(__FILE__).usec.should == 0
        end
      rescue Errno::ENOENT => e
        # Native Windows don't have stat command.
        skip e.message
      end
    end
  end

  it "raises an Errno::ENOENT exception if the file is not found" do
    -> { File.atime('a_fake_file') }.should.raise(Errno::ENOENT)
  end

  it "accepts an object that has a #to_path method" do
    File.atime(mock_to_path(@file))
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      utf8_path = tmp("file_atime_utf8_path_\u{3042}.txt")
      # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
      non_utf8_path = utf8_path.encode(Encoding::Windows_31J)

      begin
        touch(utf8_path)
        File.atime(non_utf8_path).should.is_a?(Time)
      ensure
        rm_r utf8_path
        rm_r non_utf8_path
      end
    end
  end
end

describe "File#atime" do
  before :each do
    @name = File.expand_path(__FILE__)
    @file = File.open(@name)
  end

  after :each do
    @file.close rescue nil
  end

  it "returns the last access time to self" do
    @file.atime
    @file.atime.should.is_a?(Time)
  end
end
