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
    result.should be_true
  end

  it "returns false for non-empty directories" do
    result = Dir.empty? __dir__
    result.should be_false
  end

  it "returns false for a non-directory" do
    result = Dir.empty? __FILE__
    result.should be_false
  end

  it "raises ENOENT for nonexistent directories" do
    -> { Dir.empty? tmp("nonexistent") }.should raise_error(Errno::ENOENT)
  end
end
