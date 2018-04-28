require_relative '../../spec_helper'

describe 'TracePoint#enable' do
  def test; end

  describe 'without a block' do
    it 'returns true if trace was enabled' do
      event_name = nil
      trace = TracePoint.new(:call) do |tp|
        event_name = tp.event
      end

      test
      event_name.should == nil

      trace.enable
      begin
        test
        event_name.should equal(:call)
      ensure
        trace.disable
      end
    end

    it 'returns false if trace was disabled' do
      event_name, method_name = nil, nil
      trace = TracePoint.new(:call) do |tp|
        event_name = tp.event
        method_name = tp.method_id
      end

      trace.enable.should be_false
      begin
        event_name.should equal(:call)
        test
        method_name.equal?(:test).should be_true
      ensure
        trace.disable
      end

      event_name, method_name = nil
      test
      method_name.equal?(:test).should be_false
      event_name.should equal(nil)

      trace.enable.should be_false
      begin
        event_name.should equal(:call)
        test
        method_name.equal?(:test).should be_true
      ensure
        trace.disable
      end
    end
  end

  describe 'with a block' do
    it 'enables the trace object within a block' do
      event_name = nil
      TracePoint.new(:line) do |tp|
        event_name = tp.event
      end.enable { event_name.should equal(:line) }
    end

    ruby_bug "#14057", ""..."2.5" do
      it 'can accept arguments within a block but it should not yield arguments' do
        event_name = nil
        trace = TracePoint.new(:line) { |tp| event_name = tp.event }
        trace.enable do |*args|
          event_name.should equal(:line)
          args.should == []
        end
        trace.enabled?.should be_false
      end
    end

    it 'enables trace object on calling with a block if it was already enabled' do
      enabled = nil
      trace = TracePoint.new(:line) {}
      trace.enable
      begin
        trace.enable { enabled = trace.enabled? }
        enabled.should == true
      ensure
        trace.disable
      end
    end

    it 'returns value returned by the block' do
      trace = TracePoint.new(:line) {}
      trace.enable { true; 'test' }.should == 'test'
    end

    it 'disables the trace object outside the block' do
      event_name = nil
      trace = TracePoint.new(:line) { |tp|event_name = tp.event }
      trace.enable { '2 + 2' }
      event_name.should equal(:line)
      trace.enabled?.should be_false
    end
  end
end
