require 'test/unit'

class TestEncoding < Test::Unit::TestCase

  # Test basic encoding methods: list, find, name
  def test_encoding
    encodings = Encoding.list
    assert_equal(encodings.empty?, false)

    encodings.each do |e|
      assert_equal(e, Encoding.find(e.name))
      assert_equal(e, Encoding.find(e.name.upcase))
      assert_equal(e, Encoding.find(e.name.capitalize))
      assert_equal(e, Encoding.find(e.name.downcase))
    end
  end

  # Test that Encoding objects can't be copied
  # And that they can be compared by object_id
  def test_singleton
    encodings = Encoding.list
    encodings.each do |e|
      assert_raise(TypeError) { e.dup }
      assert_raise(TypeError) { e.clone }
      assert_equal(e.object_id, Marshal.load(Marshal.dump(e)).object_id)
    end    
  end
end
