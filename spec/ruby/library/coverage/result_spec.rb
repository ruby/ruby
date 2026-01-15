require_relative '../../spec_helper'
require 'coverage'

describe 'Coverage.result' do
  before :all do
    @class_file = fixture __FILE__, 'some_class.rb'
    @config_file = fixture __FILE__, 'start_coverage.rb'
    @eval_code_file = fixture __FILE__, 'eval_code.rb'
    @with_begin_file = fixture __FILE__, 'code_with_begin.rb'
  end

  before :each do
    Coverage.running?.should == false
  end

  after :each do
    $LOADED_FEATURES.delete(@class_file)
    $LOADED_FEATURES.delete(@config_file)
    $LOADED_FEATURES.delete(@eval_code_file)
    $LOADED_FEATURES.delete(@with_begin_file)

    Coverage.result if Coverage.running?
  end

  it 'gives the covered files as a hash with arrays of count or nil' do
    Coverage.start
    require @class_file.chomp('.rb')
    result = Coverage.result

    result.should == {
      @class_file => [
        nil, nil, 1, nil, nil, 1, nil, nil, 0, nil, nil, nil, nil, nil, nil, nil
      ]
    }
  end

  it 'returns results for each mode separately when enabled :all modes' do
    Coverage.start(:all)
    require @class_file.chomp('.rb')
    result = Coverage.result

    result.should == {
      @class_file => {
        lines: [
          nil, nil, 1, nil, nil, 1, nil, nil, 0, nil, nil, nil, nil, nil, nil, nil
        ],
        branches: {},
        methods: {
          [SomeClass, :some_method, 6, 2, 11, 5] => 0
        }
      }
    }
  end

  it 'returns results for each mode separately when enabled any mode explicitly' do
    Coverage.start(lines: true)
    require @class_file.chomp('.rb')
    result = Coverage.result

    result.should == {
      @class_file =>
        {
          lines: [
            nil, nil, 1, nil, nil, 1, nil, nil, 0, nil, nil, nil, nil, nil, nil, nil
          ]
        }
    }
  end

  it 'no requires/loads should give empty hash' do
    Coverage.start
    result = Coverage.result

    result.should == {}
  end

  it 'second call should give exception' do
    Coverage.start
    require @class_file.chomp('.rb')
    Coverage.result
    -> {
      Coverage.result
    }.should raise_error(RuntimeError, 'coverage measurement is not enabled')
  end

  it 'second run should give same result' do
    Coverage.start
    load @class_file
    result1 = Coverage.result

    Coverage.start
    load @class_file
    result2 = Coverage.result

    result2.should == result1
  end

  it 'second run without load/require should give empty hash' do
    Coverage.start
    require @class_file.chomp('.rb')
    Coverage.result

    Coverage.start
    result = Coverage.result

    result.should == {}
  end

  it 'does not include the file starting coverage since it is not tracked' do
    require @config_file.chomp('.rb')
    Coverage.result.should_not include(@config_file)
  end

  it 'returns the correct results when eval coverage is enabled' do
    Coverage.supported?(:eval).should == true

    Coverage.start(lines: true, eval: true)
    require @eval_code_file.chomp('.rb')
    result = Coverage.result

    result.should == {
      @eval_code_file => {
        lines: [1, nil, 1, nil, 1, 1, nil, nil, nil, nil, 1]
      }
    }
  end

  it 'returns the correct results when eval coverage is disabled' do
    Coverage.supported?(:eval).should == true

    Coverage.start(lines: true, eval: false)
    require @eval_code_file.chomp('.rb')
    result = Coverage.result

    result.should == {
      @eval_code_file => {
        lines: [1, nil, 1, nil, 1, nil, nil, nil, nil, nil, 1]
      }
    }
  end

  it "disables coverage measurement when stop option is not specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    Coverage.result
    Coverage.running?.should == false
  end

  it "disables coverage measurement when stop: true option is specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    -> {
      Coverage.result(stop: true)
    }.should complain(/warning: stop implies clear/)

    Coverage.running?.should == false
  end

  it "does not disable coverage measurement when stop: false option is specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    Coverage.result(stop: false)
    Coverage.running?.should == true
  end

  it "does not disable coverage measurement when stop option is not specified but clear: true specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    Coverage.result(clear: true)
    Coverage.running?.should == true
  end

  it "does not disable coverage measurement when stop option is not specified but clear: false specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    Coverage.result(clear: false)
    Coverage.running?.should == true
  end

  it "disables coverage measurement when stop: true and clear: true specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    Coverage.result(stop: true, clear: true)
    Coverage.running?.should == false
  end

  it "disables coverage measurement when stop: true and clear: false specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    -> {
      Coverage.result(stop: true, clear: false)
    }.should complain(/warning: stop implies clear/)

    Coverage.running?.should == false
  end

  it "does not disable coverage measurement when stop: false and clear: true specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    Coverage.result(stop: false, clear: true)
    Coverage.running?.should == true
  end

  it "does not disable coverage measurement when stop: false and clear: false specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    Coverage.result(stop: false, clear: false)
    Coverage.running?.should == true
  end

  it "resets counters (remove them) when stop: true specified but clear option is not specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    -> {
      Coverage.result(stop: true) # clears counters
    }.should complain(/warning: stop implies clear/)

    Coverage.start
    Coverage.peek_result.should == {}
  end

  it "resets counters (remove them) when stop: true and clear: true specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    Coverage.result(stop: true, clear: true) # clears counters

    Coverage.start
    Coverage.peek_result.should == {}
  end

  it "resets counters (remove them) when stop: true and clear: false specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    -> {
      Coverage.result(stop: true, clear: false) # clears counters
    }.should complain(/warning: stop implies clear/)

    Coverage.start
    Coverage.peek_result.should == {}
  end

  it "resets counters (remove them) when both stop and clear options are not specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    Coverage.result # clears counters

    Coverage.start
    Coverage.peek_result.should == {}
  end

  it "clears counters (sets 0 values) when stop is not specified but clear: true specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    Coverage.result(clear: true) # clears counters

    Coverage.peek_result.should == {
      @class_file => [
        nil, nil, 0, nil, nil, 0, nil, nil, 0, nil, nil, nil, nil, nil, nil, nil
      ]
    }
  end

  it "does not clear counters when stop is not specified but clear: false specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    result = Coverage.result(clear: false) # doesn't clear counters
    result.should == {
      @class_file => [
        nil, nil, 1, nil, nil, 1, nil, nil, 0, nil, nil, nil, nil, nil, nil, nil
      ]
    }

    Coverage.peek_result.should == result
  end

  it "does not clear counters when stop: false and clear is not specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    result = Coverage.result(stop: false) # doesn't clear counters
    result.should == {
      @class_file => [
        nil, nil, 1, nil, nil, 1, nil, nil, 0, nil, nil, nil, nil, nil, nil, nil
      ]
    }

    Coverage.peek_result.should == result
  end

  it "clears counters (sets 0 values) when stop: false and clear: true specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    Coverage.result(stop: false, clear: true) # clears counters

    Coverage.peek_result.should == {
      @class_file => [
        nil, nil, 0, nil, nil, 0, nil, nil, 0, nil, nil, nil, nil, nil, nil, nil
      ]
    }
  end

  it "does not clear counters when stop: false and clear: false specified" do
    Coverage.start
    require @class_file.chomp('.rb')

    result = Coverage.result(stop: false, clear: false) # doesn't clear counters
    result.should == {
      @class_file => [
        nil, nil, 1, nil, nil, 1, nil, nil, 0, nil, nil, nil, nil, nil, nil, nil
      ]
    }

    Coverage.peek_result.should == result
  end

  it 'covers 100% lines with begin' do
    Coverage.start
    require @with_begin_file.chomp('.rb')
    result = Coverage.result

    result.should == {
      @with_begin_file => [
        nil, 1, nil
      ]
    }
  end
end
