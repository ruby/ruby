require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint#enable' do
  describe 'without a block' do
    it 'returns false if trace was disabled' do
      called = false
      trace = TracePoint.new(:line) do |tp|
        next unless TracePointSpec.target_thread?
        called = true
      end

      line_event = true
      called.should == false

      ret = trace.enable
      begin
        ret.should == false
        line_event = true
        called.should == true
      ensure
        trace.disable
      end
    end

    it 'returns true if trace was already enabled' do
      called = false
      trace = TracePoint.new(:line) do |tp|
        next unless TracePointSpec.target_thread?
        called = true
      end

      line_event = true
      called.should == false

      ret = trace.enable
      begin
        ret.should == false

        trace.enable.should == true

        line_event = true
        called.should == true
      ensure
        trace.disable
        trace.should_not.enabled?
      end
    end
  end

  describe 'with a block' do
    it 'enables the trace object within a block' do
      event_name = nil
      TracePoint.new(:line) do |tp|
        next unless TracePointSpec.target_thread?
        event_name = tp.event
      end.enable { event_name.should equal(:line) }
    end

    it 'enables the trace object for any thread' do
      threads = []
      trace = TracePoint.new(:line) do |tp|
        # Runs on purpose on any Thread
        threads << Thread.current
      end

      thread = nil
      trace.enable do
        line_event = true
        thread = Thread.new do
          event_in_other_thread = true
        end
        thread.join
      end

      threads = threads.uniq
      threads.should.include?(Thread.current)
      threads.should.include?(thread)
    end

    it 'can accept arguments within a block but it should not yield arguments' do
      event_name = nil
      trace = TracePoint.new(:line) do |tp|
        next unless TracePointSpec.target_thread?
        event_name = tp.event
      end
      trace.enable do |*args|
        event_name.should equal(:line)
        args.should == []
      end
      trace.should_not.enabled?
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

    it 'returns the return value of the block' do
      trace = TracePoint.new(:line) {}
      trace.enable { 42 }.should == 42
    end

    it 'disables the trace object outside the block' do
      called = false
      trace = TracePoint.new(:line) do
        next unless TracePointSpec.target_thread?
        called = true
      end
      trace.enable {
        line_event = true
      }
      called.should == true
      trace.should_not.enabled?
    end
  end

  describe "when nested" do
    it "enables both TracePoints but only calls the respective callbacks" do
      called = false
      first = TracePoint.new(:line) do |tp|
        next unless TracePointSpec.target_thread?
        called = true
      end

      all = []
      inspects = []
      second = TracePoint.new(:line) { |tp|
        next unless TracePointSpec.target_thread?
        all << tp
        inspects << tp.inspect
      }

      line = nil
      first.enable do
        second.enable do
          line = __LINE__
        end
      end

      all.uniq.should == [second]
      inspects.uniq.should == ["#<TracePoint:line #{__FILE__}:#{line}>"]
      called.should == true
    end
  end

  ruby_version_is "2.6" do
    describe 'target: option' do
      before :each do
        ScratchPad.record []
      end

      it 'enables trace point for specific location' do
        trace = TracePoint.new(:call) do |tp|
          next unless TracePointSpec.target_thread?
          ScratchPad << tp.method_id
        end

        obj = Object.new
        def obj.foo; end
        def obj.bar; end

        trace.enable(target: obj.method(:foo)) do
          obj.foo
          obj.bar
        end

        ScratchPad.recorded.should == [:foo]
      end

      it 'traces all the events triggered in specified location' do
        trace = TracePoint.new(:line, :call, :return, :b_call, :b_return) do |tp|
          next unless TracePointSpec.target_thread?
          ScratchPad << tp.event
        end

        obj = Object.new
        def obj.foo
          bar
          -> {}.call
        end
        def obj.bar; end

        trace.enable(target: obj.method(:foo)) do
          obj.foo
        end

        ScratchPad.recorded.uniq.sort.should == [:call, :return, :b_call, :b_return, :line].sort
      end

      it 'does not trace events in nested locations' do
        trace = TracePoint.new(:call) do |tp|
          next unless TracePointSpec.target_thread?
          ScratchPad << tp.method_id
        end

        obj = Object.new
        def obj.foo
          bar
        end
        def obj.bar
          baz
        end
        def obj.baz
        end

        trace.enable(target: obj.method(:foo)) do
          obj.foo
        end

        ScratchPad.recorded.should == [:foo]
      end

      it "traces some events in nested blocks" do
        klass = Class.new do
          def foo
            1.times do
              1.times do
                bar do
                end
              end
            end
          end

          def bar(&blk)
            blk.call
          end
        end

        trace = TracePoint.new(:b_call) do |tp|
          next unless TracePointSpec.target_thread?
          ScratchPad << tp.lineno
        end

        obj = klass.new
        _, lineno = obj.method(:foo).source_location

        trace.enable(target: obj.method(:foo)) do
          obj.foo
        end

        ScratchPad.recorded.should == (lineno+1..lineno+3).to_a
      end

      describe 'option value' do
        it 'accepts Method' do
          trace = TracePoint.new(:call) do |tp|
            next unless TracePointSpec.target_thread?
            ScratchPad << tp.method_id
          end

          obj = Object.new
          def obj.foo; end

          trace.enable(target: obj.method(:foo)) do
            obj.foo
          end

          ScratchPad.recorded.should == [:foo]
        end

        it 'accepts UnboundMethod' do
          trace = TracePoint.new(:call) do |tp|
            next unless TracePointSpec.target_thread?
            ScratchPad << tp.method_id
          end

          klass = Class.new do
            def foo; end
          end

          unbound_method = klass.instance_method(:foo)
          trace.enable(target: unbound_method) do
            klass.new.foo
          end

          ScratchPad.recorded.should == [:foo]
        end

        it 'accepts Proc' do
          trace = TracePoint.new(:b_call) do |tp|
            next unless TracePointSpec.target_thread?
            ScratchPad << tp.lineno
          end

          block = proc {}
          _, lineno = block.source_location

          trace.enable(target: block) do
            block.call
          end

          ScratchPad.recorded.should == [lineno]
          lineno.should be_kind_of(Integer)
        end
      end

      it "raises ArgumentError if target object cannot trigger specified event" do
        trace = TracePoint.new(:call) do |tp|
          next unless TracePointSpec.target_thread?
          ScratchPad << tp.method_id
        end

        block = proc {}

        -> {
          trace.enable(target: block) do
            block.call # triggers :b_call and :b_return events
          end
        }.should raise_error(ArgumentError, /can not enable any hooks/)
      end

      it "raises ArgumentError if passed not Method/UnboundMethod/Proc" do
        trace = TracePoint.new(:call) {}

        -> {
          trace.enable(target: Object.new) do
          end
        }.should raise_error(ArgumentError, /specified target is not supported/)
      end

      context "nested enabling and disabling" do
        it "raises ArgumentError if trace point already enabled with target is re-enabled with target" do
          trace = TracePoint.new(:b_call) {}

          -> {
            trace.enable(target: -> {}) do
              trace.enable(target: -> {}) do
              end
            end
          }.should raise_error(ArgumentError, /can't nest-enable a targett?ing TracePoint/)
        end

        it "raises ArgumentError if trace point already enabled without target is re-enabled with target" do
          trace = TracePoint.new(:b_call) {}

          -> {
            trace.enable do
              trace.enable(target: -> {}) do
              end
            end
          }.should raise_error(ArgumentError, /can't nest-enable a targett?ing TracePoint/)
        end

        it "raises ArgumentError if trace point already enabled with target is re-enabled without target" do
          trace = TracePoint.new(:b_call) {}

          -> {
            trace.enable(target: -> {}) do
              trace.enable do
              end
            end
          }.should raise_error(ArgumentError, /can't nest-enable a targett?ing TracePoint/)
        end

        it "raises ArgumentError if trace point already enabled with target is disabled with block" do
          trace = TracePoint.new(:b_call) {}

          -> {
            trace.enable(target: -> {}) do
              trace.disable do
              end
            end
          }.should raise_error(ArgumentError, /can't disable a targett?ing TracePoint in a block/)
        end

        it "traces events when trace point with target is enabled in another trace point enabled without target" do
          trace_outer = TracePoint.new(:b_call) do |tp|
            next unless TracePointSpec.target_thread?
            ScratchPad << :outer
          end

          trace_inner = TracePoint.new(:b_call) do |tp|
            next unless TracePointSpec.target_thread?
            ScratchPad << :inner
          end

          target = -> {}

          trace_outer.enable do
            trace_inner.enable(target: target) do
              target.call
            end
          end

          ScratchPad.recorded.should == [:outer, :outer, :outer, :inner]
        end

        it "traces events when trace point with target is enabled in another trace point enabled with target" do
          trace_outer = TracePoint.new(:b_call) do |tp|
            next unless TracePointSpec.target_thread?
            ScratchPad << :outer
          end

          trace_inner = TracePoint.new(:b_call) do |tp|
            next unless TracePointSpec.target_thread?
            ScratchPad << :inner
          end

          target = -> {}

          trace_outer.enable(target: target) do
            trace_inner.enable(target: target) do
              target.call
            end
          end

          ScratchPad.recorded.should == [:inner, :outer]
        end

        it "traces events when trace point without target is enabled in another trace point enabled with target" do
          trace_outer = TracePoint.new(:b_call) do |tp|
            next unless TracePointSpec.target_thread?
            ScratchPad << :outer
          end

          trace_inner = TracePoint.new(:b_call) do |tp|
            next unless TracePointSpec.target_thread?
            ScratchPad << :inner
          end

          target = -> {}

          trace_outer.enable(target: target) do
            trace_inner.enable do
              target.call
            end
          end

          ScratchPad.recorded.should == [:inner, :inner, :outer]
        end
      end
    end

    describe 'target_line: option' do
      before :each do
        ScratchPad.record []
      end

      it "traces :line events only on specified line of code" do
        trace = TracePoint.new(:line) do |tp|
          next unless TracePointSpec.target_thread?
          ScratchPad << tp.lineno
        end

        target = -> {
          x = 1
          y = 2      # <= this line is target
          z = x + y
        }
        _, lineno = target.source_location
        target_line = lineno + 2

        trace.enable(target_line: target_line, target: target) do
          target.call
        end

        ScratchPad.recorded.should == [target_line]
      end

      it "raises ArgumentError if :target option isn't specified" do
        trace = TracePoint.new(:line) {}

        -> {
          trace.enable(target_line: 67) do
          end
        }.should raise_error(ArgumentError, /only target_line is specified/)
      end

      it "raises ArgumentError if :line event isn't registered" do
        trace = TracePoint.new(:call) {}

        target = -> {
          x = 1
          y = 2     # <= this line is target
          z = x + y
        }
        _, lineno = target.source_location
        target_line = lineno + 2

        -> {
          trace.enable(target_line: target_line, target: target) do
          end
        }.should raise_error(ArgumentError, /target_line is specified, but line event is not specified/)
      end

      it "raises ArgumentError if :target_line value is out of target code lines range" do
        trace = TracePoint.new(:line) {}

        -> {
          trace.enable(target_line: 1, target: -> { }) do
          end
        }.should raise_error(ArgumentError, /can not enable any hooks/)
      end

      it "raises TypeError if :target_line value couldn't be coerced to Integer" do
        trace = TracePoint.new(:line) {}

        -> {
          trace.enable(target_line: Object.new, target: -> { }) do
          end
        }.should raise_error(TypeError, /no implicit conversion of \w+? into Integer/)
      end

      it "raises ArgumentError if :target_line value is negative" do
        trace = TracePoint.new(:line) {}

        -> {
          trace.enable(target_line: -2, target: -> { }) do
          end
        }.should raise_error(ArgumentError, /can not enable any hooks/)
      end

      it "accepts value that could be coerced to Integer" do
        trace = TracePoint.new(:line) do |tp|
          next unless TracePointSpec.target_thread?
          ScratchPad << tp.lineno
        end

        target = -> {
          x = 1         #  <= this line is target
        }
        _, lineno = target.source_location
        target_line = lineno + 1

        trace.enable(target_line: target_line.to_r, target: target) do
          target.call
        end

        ScratchPad.recorded.should == [target_line]
      end
    end
  end
end
