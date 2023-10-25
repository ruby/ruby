require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "3.1" do
  describe 'TracePoint.allow_reentry' do
    it 'allows the reentrance in a given block' do
      event_lines = []
      l1 = l2 = l3 = l4 = nil
      TracePoint.new(:line) do |tp|
        next unless TracePointSpec.target_thread?

        event_lines << tp.lineno
        next if (__LINE__ + 2 .. __LINE__ + 4).cover?(tp.lineno)
        TracePoint.allow_reentry do
          a = 1; l3 = __LINE__
          b = 2; l4 = __LINE__
        end
      end.enable do
        c = 3; l1 = __LINE__
        d = 4; l2 = __LINE__
      end

      event_lines.should == [l1, l3, l4, l2, l3, l4]
    end

    it 'raises RuntimeError when not called inside a TracePoint' do
      -> {
        TracePoint.allow_reentry{}
      }.should raise_error(RuntimeError)
    end
  end
end
