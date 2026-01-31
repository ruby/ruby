require_relative '../../spec_helper'

describe "Encoding#ascii_compatible?" do
  it "returns true if self represents an ASCII-compatible encoding" do
    Encoding::UTF_8.ascii_compatible?.should be_true
  end

  it "returns false if self does not represent an ASCII-compatible encoding" do
    Encoding::UTF_16LE.ascii_compatible?.should be_false
  end

  it "returns false for UTF_16 and UTF_32" do
    Encoding::UTF_16.should_not.ascii_compatible?
    Encoding::UTF_32.should_not.ascii_compatible?
  end

  it "is always false for dummy encodings" do
    Encoding.list.select(&:dummy?).each do |encoding|
      encoding.should_not.ascii_compatible?
    end
  end
end
