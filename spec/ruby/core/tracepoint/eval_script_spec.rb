require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "2.6" do
  describe "#eval_script" do
    ScratchPad.record []

    script = <<-CODE
      def foo
        p :hello
      end
    CODE

    TracePoint.new(:script_compiled) do |e|
      ScratchPad << e.eval_script
    end.enable do
      eval script
    end

    ScratchPad.recorded.should == [script]
  end
end
