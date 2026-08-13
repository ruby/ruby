require_relative '../../spec_helper'

describe "File.mtime" do
  before :each do
    @filename = tmp('i_exist')
    touch(@filename) { @mtime = Time.now }
  end

  after :each do
    rm_r @filename
  end

  it "returns the modification Time of the file" do
    File.mtime(@filename).should.is_a?(Time)
    File.mtime(@filename).should be_close(@mtime, TIME_TOLERANCE)
  end

  platform_is :linux, :windows do
    unless ENV.key?('TRAVIS') # https://bugs.ruby-lang.org/issues/17926
      it "returns the modification Time of the file with microseconds" do
        supports_subseconds = Integer(`stat -c%y #{__FILE__}`[/\.(\d{1,6})/, 1], 10)
        if supports_subseconds != 0
          expected_time = Time.at(Time.now.to_i + 0.123456)
          File.utime 0, expected_time, @filename
          File.mtime(@filename).usec.should == expected_time.usec
        else
          File.mtime(__FILE__).usec.should == 0
        end
      rescue Errno::ENOENT => e
        # Windows don't have stat command.
        skip e.message
      end
    end
  end

  it "raises an Errno::ENOENT exception if the file is not found" do
    -> { File.mtime('bogus') }.should.raise(Errno::ENOENT)
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      utf8_path = tmp("file_mtime_utf8_path_\u{3042}.txt")
      # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
      non_utf8_path = utf8_path.encode(Encoding::Windows_31J)

      begin
        touch(utf8_path)
        File.mtime(non_utf8_path).should.is_a?(Time)
      ensure
        rm_r utf8_path
        rm_r non_utf8_path
      end
    end
  end
end

describe "File#mtime" do
  before :each do
    @filename = tmp('i_exist')
    @f = File.open(@filename, 'w')
  end

  after :each do
    @f.close
    rm_r @filename
  end

  it "returns the modification Time of the file" do
    @f.mtime.should.is_a?(Time)
  end

end
