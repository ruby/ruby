require_relative "../rexml_test_utils"

module REXMLTests
  class DefaultFormatterTest < Test::Unit::TestCase
    def format(node)
      formatter = REXML::Formatters::Default.new
      output = ""
      formatter.write(node, output)
      output
    end

    class InstructionTest < self
      def test_content_nil
        instruction = REXML::Instruction.new("target")
        assert_equal("<?target?>", format(instruction))
      end
    end
  end
end
