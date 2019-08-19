require_relative "rexml_test_utils"

module REXMLTests
  class AttributeTest < Test::Unit::TestCase
    def test_empty_prefix
      error = assert_raise(ArgumentError) do
        REXML::Attribute.new(":x")
      end
      assert_equal("name must be " +
                   "\#{PREFIX}:\#{LOCAL_NAME} or \#{LOCAL_NAME}: <\":x\">",
                   error.message)
    end
  end
end
