require_relative '../../spec_helper'

describe "Dir.empty?" do
  before :all do
    @empty_dir = tmp("empty_dir")
    mkdir_p @empty_dir
  end

  after :all do
    rm_r @empty_dir
  end

  it "returns true for empty directories" do
    result = Dir.empty? @empty_dir
    result.should == true
  end

  it "returns false for non-empty directories" do
    result = Dir.empty? __dir__
    result.should == false
  end

  it "returns false for a non-directory" do
    result = Dir.empty? __FILE__
    result.should == false
  end

  it "raises ENOENT for nonexistent directories" do
    -> { Dir.empty? tmp("nonexistent") }.should.raise(Errno::ENOENT)
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      dir = tmp("dir_empty_\u{3042}")
      non_utf8_dir = dir.encode(Encoding::Windows_31J)

      begin
        mkdir_p(dir)
        Dir.empty?(non_utf8_dir).should == true
      ensure
        rm_r dir
      end
    end
  end
end
