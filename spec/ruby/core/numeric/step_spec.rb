require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/step'

describe "Numeric#step" do

  describe 'with positional args' do
    it "raises an ArgumentError when step is 0" do
      lambda { 1.step(5, 0) {} }.should raise_error(ArgumentError)
    end

    it "raises an ArgumentError when step is 0.0" do
      lambda { 1.step(2, 0.0) {} }.should raise_error(ArgumentError)
    end

    before :all do
      # This lambda definition limits to return the arguments it receives.
      # It's needed to test numeric_step behaviour with positional arguments.
      @step_args = ->(*args) { args }
    end

    it_behaves_like :numeric_step, :step

    describe "when no block is given" do
      step_enum_class = Enumerator
      ruby_version_is "2.6" do
        step_enum_class = Enumerator::ArithmeticSequence
      end

      it "returns an #{step_enum_class} when step is 0" do
        1.step(5, 0).should be_an_instance_of(step_enum_class)
      end

      it "returns an #{step_enum_class} when step is 0.0" do
        1.step(2, 0.0).should be_an_instance_of(step_enum_class)
      end

      describe "returned #{step_enum_class}" do
        describe "size" do
          ruby_version_is ""..."2.6" do
            it "raises an ArgumentError when step is 0" do
              enum = 1.step(5, 0)
              lambda { enum.size }.should raise_error(ArgumentError)
            end

            it "raises an ArgumentError when step is 0.0" do
              enum = 1.step(2, 0.0)
              lambda { enum.size }.should raise_error(ArgumentError)
            end
          end

          ruby_version_is "2.6" do
            it "is infinity when step is 0" do
              enum = 1.step(5, 0)
              enum.size.should == Float::INFINITY
            end

            it "is infinity when step is 0.0" do
              enum = 1.step(2, 0.0)
              enum.size.should == Float::INFINITY
            end
          end
        end
      end
    end

  end

  describe 'with keyword arguments' do
    it "doesn't raise an error when step is 0" do
      lambda { 1.step(to: 5, by: 0) { break } }.should_not raise_error
    end

    it "doesn't raise an error when step is 0.0" do
      lambda { 1.step(to: 2, by: 0.0) { break } }.should_not raise_error
    end

    it "should loop over self when step is 0 or 0.0" do
      1.step(to: 2, by: 0.0).take(5).should eql [1.0, 1.0, 1.0, 1.0, 1.0]
      1.step(to: 2, by: 0).take(5).should eql [1, 1, 1, 1, 1]
      1.1.step(to: 2, by: 0).take(5).should eql [1.1, 1.1, 1.1, 1.1, 1.1]
    end

    describe "when no block is given" do
      describe "returned Enumerator" do
        describe "size" do
          it "should return infinity_value when limit is nil" do
            1.step(by: 42).size.should == infinity_value
          end

          it "should return infinity_value when step is 0" do
            1.step(to: 5, by: 0).size.should == infinity_value
          end

          it "should return infinity_value when step is 0.0" do
            1.step(to: 2, by: 0.0).size.should == infinity_value
          end

          it "should return infinity_value when ascending towards a limit of Float::INFINITY" do
            1.step(to: Float::INFINITY, by: 42).size.should == infinity_value
          end

          it "should return infinity_value when decending towards a limit of -Float::INFINITY" do
            1.step(to: -Float::INFINITY, by: -42).size.should == infinity_value
          end

          it "should return 1 when the both limit and step are Float::INFINITY" do
            1.step(to: Float::INFINITY, by: Float::INFINITY).size.should == 1
          end

          it "should return 1 when the both limit and step are -Float::INFINITY" do
            1.step(to: -Float::INFINITY, by: -Float::INFINITY).size.should == 1
          end
        end
      end
    end

    before :all do
      # This lambda transforms a positional step method args into
      # keyword arguments.
      # It's needed to test numeric_step behaviour with keyword arguments.
      @step_args = ->(*args) do
        kw_args = {to: args[0]}
        kw_args[:by] = args[1] if args.size == 2
        [kw_args]
      end
    end
    it_behaves_like :numeric_step, :step
  end

  describe 'with mixed arguments' do
    it "doesn't raise an error when step is 0" do
      lambda { 1.step(5, by: 0) { break } }.should_not raise_error
    end

    it "doesn't raise an error when step is 0.0" do
      lambda { 1.step(2, by: 0.0) { break } }.should_not raise_error
    end

    it "raises a ArgumentError when limit and to are defined" do
      lambda { 1.step(5, 1, to: 5) { break } }.should raise_error(ArgumentError)
    end

    it "raises a ArgumentError when step and by are defined" do
      lambda { 1.step(5, 1, by: 5) { break } }.should raise_error(ArgumentError)
    end

    it "should loop over self when step is 0 or 0.0" do
      1.step(2, by: 0.0).take(5).should eql [1.0, 1.0, 1.0, 1.0, 1.0]
      1.step(2, by: 0).take(5).should eql [1, 1, 1, 1, 1]
      1.1.step(2, by: 0).take(5).should eql [1.1, 1.1, 1.1, 1.1, 1.1]
    end

    describe "when no block is given" do
      describe "returned Enumerator" do
        describe "size" do
          it "should return infinity_value when step is 0" do
            1.step(5, by: 0).size.should == infinity_value
          end

          it "should return infinity_value when step is 0.0" do
            1.step(2, by: 0.0).size.should == infinity_value
          end
        end
      end
    end
    before :all do
      # This lambda definition transforms a positional step method args into
      # a mix of positional and keyword arguments.
      # It's needed to test numeric_step behaviour with positional mixed with
      # keyword arguments.
      @step_args = ->(*args) do
        if args.size == 2
          [args[0], {by: args[1]}]
        else
          args
        end
      end
    end
    it_behaves_like :numeric_step, :step
  end
end
