require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "2.6" do
  describe "TracePoint#eval_script" do
    it "is the evald source code" do
      ScratchPad.record []

      script = <<-CODE
        def foo
          p :hello
        end
      CODE

      TracePoint.new(:script_compiled) do |e|
        next unless TracePointSpec.target_thread?
        ScratchPad << e.eval_script
      end.enable do
        eval script
      end

      ScratchPad.recorded.should == [script]
    end
  end
end
