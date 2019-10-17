require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe :string_grapheme_clusters, shared: true do
  it "passes each grapheme cluster in self to the given block" do
    a = []
    # test string: abc[rainbow flag emoji][paw prints]
    "ab\u{1f3f3}\u{fe0f}\u{200d}\u{1f308}\u{1F43E}".send(@method) { |c| a << c }
    a.should == ['a', 'b', "\u{1f3f3}\u{fe0f}\u{200d}\u{1f308}", "\u{1F43E}"]
  end

  it "returns self" do
    s = StringSpecs::MyString.new "ab\u{1f3f3}\u{fe0f}\u{200d}\u{1f308}\u{1F43E}"
    s.send(@method) {}.should equal(s)
  end
end
