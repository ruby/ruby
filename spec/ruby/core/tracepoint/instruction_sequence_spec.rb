require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "2.6" do
  describe "TracePoint#instruction_sequence" do
    it "is an instruction sequence" do
      ScratchPad.record []

      script = <<-CODE
        def foo
          p :hello
        end
      CODE

      TracePoint.new(:script_compiled) do |e|
        ScratchPad << e.instruction_sequence
      end.enable do
        eval script
      end

      ScratchPad.recorded.size.should == 1
      ScratchPad.recorded[0].class.should == RubyVM::InstructionSequence
    end
  end
end
