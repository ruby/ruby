require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#named_captures" do
  before do
    @s = StringScanner.new('Fri Dec 12 1975 14:39')
  end

  it "returns a hash of names and matched substrings for named capturing groups in a regular expression of the most recent matching" do
    @s.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\d+)/)
    @s.named_captures.should == {"wday" => "Fri", "month" => "Dec", "day" => "12"}
  end

  it "returns {} if there are no named capturing groups" do
    @s.exist?(/(\w+) (\w+) (\d+)/)
    @s.named_captures.should == {}
  end

  # https://github.com/ruby/strscan/issues/132
  ruby_bug "", ""..."3.3" do # fixed in strscan v3.0.7
    it "returns {} if there is no any matching done" do
      @s.named_captures.should == {}
    end
  end

  it "returns nil for an optional named capturing group if it doesn't match" do
    @s.exist?(/(?<wday>\w+) (?<month>\w+) (?<day>\s+)?/)
    @s.named_captures.should == {"wday" => "Fri", "month" => "Dec", "day" => nil}
  end
end
