require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/step'

describe "Numeric#step" do

  describe 'with positional args' do
    it "raises an ArgumentError when step is 0" do
      -> { 1.step(5, 0) {} }.should raise_error(ArgumentError)
    end

    it "raises an ArgumentError when step is 0.0" do
      -> { 1.step(2, 0.0) {} }.should raise_error(ArgumentError)
    end

    before :all do
      # This lambda definition limits to return the arguments it receives.
      # It's needed to test numeric_step behaviour with positional arguments.
      @step = -> receiver, *args, &block { receiver.step(*args, &block) }
    end
    it_behaves_like :numeric_step, :step

    describe "when no block is given" do
      step_enum_class = Enumerator::ArithmeticSequence

      describe "returned #{step_enum_class}" do
        describe "size" do
          it "defaults to an infinite size" do
            enum = 1.step
            enum.size.should == Float::INFINITY
          end
        end

        describe "type" do
          it "returns an instance of Enumerator::ArithmeticSequence" do
            1.step(10).class.should == Enumerator::ArithmeticSequence
          end
        end
      end
    end
  end

  describe 'with keyword arguments' do
    describe "when no block is given" do
      describe "returned Enumerator" do
        describe "size" do
          it "should return infinity_value when limit is nil" do
            1.step(by: 42).size.should == infinity_value
          end

          it "should return infinity_value when ascending towards a limit of Float::INFINITY" do
            1.step(to: Float::INFINITY, by: 42).size.should == infinity_value
          end

          it "should return infinity_value when descending towards a limit of -Float::INFINITY" do
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
      # This lambda transforms a positional step method args into  keyword arguments.
      # It's needed to test numeric_step behaviour with keyword arguments.
      @step = -> receiver, *args, &block do
        kw_args = { to: args[0] }
        kw_args[:by] = args[1] if args.size == 2
        receiver.step(**kw_args, &block)
      end
    end
    it_behaves_like :numeric_step, :step
  end

  describe 'with mixed arguments' do
    it " raises an ArgumentError when step is 0" do
      -> { 1.step(5, by: 0) { break } }.should raise_error(ArgumentError)
    end

    it "raises an ArgumentError when step is 0.0" do
      -> { 1.step(2, by: 0.0) { break } }.should raise_error(ArgumentError)
    end

    it "raises a ArgumentError when limit and to are defined" do
      -> { 1.step(5, 1, to: 5) { break } }.should raise_error(ArgumentError)
    end

    it "raises a ArgumentError when step and by are defined" do
      -> { 1.step(5, 1, by: 5) { break } }.should raise_error(ArgumentError)
    end

    describe "when no block is given" do
      describe "returned Enumerator" do
        describe "size" do
        end
      end
    end

    before :all do
      # This lambda definition transforms a positional step method args into
      # a mix of positional and keyword arguments.
      # It's needed to test numeric_step behaviour with positional mixed with
      # keyword arguments.
      @step = -> receiver, *args, &block do
        if args.size == 2
          receiver.step(args[0], by: args[1], &block)
        else
          receiver.step(*args, &block)
        end
      end
    end
    it_behaves_like :numeric_step, :step
  end
end
