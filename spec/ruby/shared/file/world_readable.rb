require_relative '../../spec_helper'

describe :file_world_readable, shared: true do

  before :each do
    @file = tmp('world-readable')
    touch @file
  end

  after :each do
    rm_r @file
  end

  platform_is_not :windows do
    it "returns nil if the file is chmod 600" do
      File.chmod(0600, @file)
      @object.world_readable?(@file).should == nil
    end

    it "returns nil if the file is chmod 000" do
      File.chmod(0000, @file)
      @object.world_readable?(@file).should == nil
    end

    it "returns nil if the file is chmod 700" do
      File.chmod(0700, @file)
      @object.world_readable?(@file).should == nil
    end
  end

  # We don't specify what the Integer is because it's system dependent
  it "returns an Integer if the file is chmod 644" do
    File.chmod(0644, @file)
    @object.world_readable?(@file).should.instance_of?(Integer)
  end

  it "returns an Integer if the file is a directory and chmod 644" do
    dir = tmp(rand().to_s + '-ww')
    Dir.mkdir(dir)
    Dir.should.exist?(dir)
    File.chmod(0644, dir)
    @object.world_readable?(dir).should.instance_of?(Integer)
    Dir.rmdir(dir)
  end

  it "coerces the argument with #to_path" do
    @object.world_readable?(mock_to_path(@file))
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      utf8_path = tmp("file_predicate_utf8_path_\u{3042}.txt")
      # Can fail with UndefinedConversionError if tmp path has non-Shift_JIS chars (e.g. Emojis, Hangul, Cyrillic, accented letters)
      non_utf8_path = utf8_path.encode(Encoding::Windows_31J)

      begin
        touch(utf8_path)
        File.chmod(0644, utf8_path)
        @object.send(@method, non_utf8_path).should.instance_of?(Integer)
      ensure
        rm_r utf8_path
        rm_r non_utf8_path
      end
    end
  end
end
