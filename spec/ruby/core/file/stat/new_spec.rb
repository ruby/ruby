require_relative '../../../spec_helper'

describe "File::Stat#initialize" do

  before :each do
    @file = tmp('i_exist')
    touch(@file) { |f| f.write "rubinius" }
    File.chmod(0755, @file)
  end

  after :each do
    rm_r @file
  end

  it "raises an exception if the file doesn't exist" do
    -> {
      File::Stat.new(tmp("i_am_a_dummy_file_that_doesnt_exist"))
    }.should.raise(Errno::ENOENT)
  end

  it "creates a File::Stat object for the given file" do
    st = File::Stat.new(@file)
    st.should.is_a?(File::Stat)
    st.ftype.should == 'file'
  end

  it "calls #to_path on non-String arguments" do
    p = mock('path')
    p.should_receive(:to_path).and_return @file
    File::Stat.new p
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      utf8_path = tmp("file_stat_new_utf8_path_\u{3042}.txt")
      # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
      non_utf8_path = utf8_path.encode(Encoding::Windows_31J)

      begin
        touch(utf8_path)
        File::Stat.new(non_utf8_path).should.is_a?(File::Stat)
      ensure
        rm_r utf8_path
        rm_r non_utf8_path
      end
    end
  end
end
