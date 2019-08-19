require_relative '../../spec_helper'

ruby_version_is "2.6" do
  describe 'TracePoint#parameters' do
    it 'returns the parameters of block' do
      f = proc {|x, y, z| }
      parameters = nil
      TracePoint.new(:b_call) {|tp| parameters = tp.parameters }.enable do
        f.call
        parameters.should == [[:opt, :x], [:opt, :y], [:opt, :z]]
      end
    end

    it 'returns the parameters of lambda block' do
      f = lambda {|x, y, z| }
      parameters = nil
      TracePoint.new(:b_call) {|tp| parameters = tp.parameters }.enable do
        f.call(1, 2, 3)
        parameters.should == [[:req, :x], [:req, :y], [:req, :z]]
      end
    end
  end
end
