require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/kernel/raise'

describe "Kernel#raise" do
  it "is a private method" do
    Kernel.private_instance_methods.should.include?(:raise)
  end

  # Shared specs expect a public #raise method.
  public_raiser = Object.new
  class << public_raiser
    public :raise
  end
  it_behaves_like :kernel_raise, :raise, public_raiser
  it_behaves_like :kernel_raise_with_cause, :raise, public_raiser
end

describe "Kernel#raise with previously rescued exception" do
  it "re-raises the previously rescued exception if no exception is specified" do
    ScratchPad.record nil

    -> do
      begin
        raise Exception, "outer"
        ScratchPad.record :no_abort
      rescue Exception
        begin
          raise StandardError, "inner"
        rescue StandardError
        end

        raise
        ScratchPad.record :no_reraise
      end
    end.should.raise(Exception, "outer")

    ScratchPad.recorded.should == nil
  end

  new_raisers = [
    -> { raise "Error" },
    -> { raise RuntimeError, "Error" },
    -> { raise RuntimeError, "Error", [] }
  ]

  re_raisers_with_cause = [
    -> e1, e2 {raise e1, cause: e2},
    -> e1, e2 {raise e1, "New message", cause: e2},
    -> e1, e2 {raise e1, "New message", [], cause: e2}
  ]

  it "re-raises a previously rescued exception without overwriting the cause" do
    check = -> second_raiser do
      begin
        begin
          begin
            raise "Error 1"
          rescue => e1
            second_raiser.call
          end
        rescue => e2
          raise "Error 3"
        end
      rescue
        e2.cause.should == e1
        raise e2
      end
    rescue => e
      e.cause.should == e1
    end

    new_raisers.each(&check)
  end

  it "re-raises a previously rescued exception with overwriting the cause when it's explicitly specified with :cause option" do
    check = -> ((raiser, re_raiser_with_cause)) do # rubocop:disable Style/StabbyLambdaParentheses
      e4 = RuntimeError.new("Error 4")
      begin
        begin
          begin
            raise "Error 1"
          rescue => e1
            raiser.call
          end
        rescue => e2
          raise "Error 3"
        end
      rescue
        e2.cause.should == e1
        re_raiser_with_cause.call(e2, e4)
      end
    rescue => e
      e.cause.should == e4
    end

    new_raisers.product(re_raisers_with_cause).each(&check)
  end

  it "re-raises a previously rescued exception without overwriting the cause when it's explicitly specified with a :cause option that has nil value" do
    check = -> ((raiser, re_raiser_with_cause)) do # rubocop:disable Style/StabbyLambdaParentheses
      begin
        begin
          begin
            raise "Error 1"
          rescue => e1
            raiser.call
          end
        rescue => e2
          raise "Error 3"
        end
      rescue
        e2.cause.should == e1
        re_raiser_with_cause.call(e2, nil)
      end
    rescue => e
      e.cause.should == e1
    end

    new_raisers.product(re_raisers_with_cause).each(&check)
  end

  it "re-raises a previously rescued exception without setting a cause implicitly" do
    check = -> raiser do
      begin
        raiser.call
      rescue => e1
        raise
      end
    rescue => e
      e.should == e1
      e.cause.should == nil
    end

    new_raisers.each(&check)
  end

  it "re-raises a previously rescued exception that has a cause without setting a cause implicitly" do
    check = -> raiser do
      begin
        raiser.call
      rescue => e1
        begin
          raise "Error 2"
        rescue => e2
          raise
        end
      end
    rescue => e
      e.should == e2
      e.cause.should == e1
    end

    new_raisers.each(&check)
  end

  it "raises a new exception with two outer rescues while setting the cause implicitly to the innermost rescued exception" do
    check = -> raiser do
      begin
        raiser.call
      rescue => e1
        begin
          raise "Error 2"
        rescue => e2
          raise "Error 3"
        end
      end
    rescue => e
      e.message.should == "Error 3"
      e.cause.should == e2
    end

    new_raisers.each(&check)
  end

  it "re-raises a previously rescued exception that doesn't have a cause and is a cause of other exception without setting a cause implicitly" do
    check = -> raiser do
      begin
        raiser.call
      rescue => e1
        begin
          raise "Error 2"
        rescue => e2
          e1.cause.should == nil
          e2.cause.should == e1
          raise e1
        end
      end
    rescue => e
      e.should == e1
      e.cause.should == nil
    end

    new_raisers.each(&check)
  end

  it "re-raises a previously rescued exception that doesn't have a cause and is a cause of other exception (that wasn't raised explicitly) without setting a cause implicitly" do
    check = -> raiser do
      begin
        raiser.call
      rescue => e1
        begin
          foo # raises NameError
        rescue => e2
          e1.cause.should == nil
          e2.cause.should == e1
          raise e1
        end
      end
    rescue => e
      e.should == e1
      e.cause.should == nil
    end

    new_raisers.each(&check)
  end

  it "re-raises a previously rescued exception that has a cause but isn't a cause of any other exception without setting a cause implicitly" do
    check = -> raiser do
      begin
        raiser.call
      rescue => e1
        begin
          raise "Error 2"
        rescue => e2
          begin
            raise "Error 3", cause: RuntimeError.new("Error 4")
          rescue => e3
            e2.cause.should == e1
            e3.cause.should_not == e2
            raise e2
          end
        end
      end
    rescue => e
      e.should == e2
      e.cause.should == e1
    end

    new_raisers.each(&check)
  end
end

describe "Kernel.raise" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:Array)
  end
end
