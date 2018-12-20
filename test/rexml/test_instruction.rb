require_relative "rexml_test_utils"

module REXMLTests
  class InstructionTest < Test::Unit::TestCase
    def test_target_nil
      error = assert_raise(ArgumentError) do
        REXML::Instruction.new(nil)
      end
      assert_equal("processing instruction target must be String or " +
                   "REXML::Instruction: <nil>",
                   error.message)
    end
  end
end
