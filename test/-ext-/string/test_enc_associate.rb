# frozen_string_literal: false
require 'test/unit'
require "-test-/string"

class Test_StrEncAssociate < Test::Unit::TestCase
  def test_frozen
    s = Bug::String.new("abc")
    s.force_encoding(Encoding::US_ASCII)
    s.freeze
    assert_raise(RuntimeError) {s.associate_encoding!(Encoding::US_ASCII)}
    assert_raise(RuntimeError) {s.associate_encoding!(Encoding::UTF_8)}
  end

  Encoding.list.select(&:dummy?).each do |enc|
    enc = enc.name.tr('-', '_')
    define_method("test_dummy_encoding_index_#{enc}") do
      assert_separately(["-r-test-/string", "-", enc], <<-"end;") #do
        enc = Encoding.const_get(ARGV[0])
        index = Bug::String.encoding_index(enc)
        assert(index < 0xffff, "<%#x> expected but was\n<%#x>" % [index & 0xffff, index])
      end;
    end
  end
end
