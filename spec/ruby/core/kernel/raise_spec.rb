require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/kernel/raise'

describe "Kernel#raise" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:raise)
  end

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
    end.should raise_error(Exception, "outer")

    ScratchPad.recorded.should be_nil
  end

  it "accepts a cause keyword argument that sets the cause" do
    cause = StandardError.new
    -> { raise("error", cause: cause) }.should raise_error(RuntimeError) { |e| e.cause.should == cause }
  end

  it "accepts a cause keyword argument that overrides the last exception" do
    begin
      raise "first raise"
    rescue => ignored
      cause = StandardError.new
      -> { raise("error", cause: cause) }.should raise_error(RuntimeError) { |e| e.cause.should == cause }
    end
  end

  it "raises an ArgumentError when only cause is given" do
    cause = StandardError.new
    -> { raise(cause: cause) }.should raise_error(ArgumentError, "only cause is given with no arguments")
  end

  it "raises an ArgumentError when only cause is given even if it has nil value" do
    -> { raise(cause: nil) }.should raise_error(ArgumentError, "only cause is given with no arguments")
  end

  it "raises an ArgumentError when given cause is not an instance of Exception" do
    -> { raise "message", cause: Object.new }.should raise_error(TypeError, "exception object expected")
  end

  it "doesn't raise an ArgumentError when given cause is nil" do
    -> { raise "message", cause: nil }.should raise_error(RuntimeError, "message")
  end

  it "allows cause equal an exception" do
    e = RuntimeError.new("message")
    -> { raise e, cause: e }.should raise_error(e)
  end

  it "doesn't set given cause when it equals an exception" do
    e = RuntimeError.new("message")

    begin
      raise e, cause: e
    rescue
    end

    e.cause.should == nil
  end

  it "raises ArgumentError when exception is part of the cause chain" do
    -> {
      begin
        raise "Error 1"
      rescue => e1
        begin
          raise "Error 2"
        rescue => e2
          begin
            raise "Error 3"
          rescue => e3
            raise e1, cause: e3
          end
        end
      end
    }.should raise_error(ArgumentError, "circular causes")
  end

  it "re-raises a rescued exception" do
    -> do
      begin
        raise StandardError, "aaa"
      rescue Exception
        begin
          raise ArgumentError
        rescue ArgumentError
        end

        # should raise StandardError "aaa"
        raise
      end
    end.should raise_error(StandardError, "aaa")
  end

  it "re-raises a previously rescued exception without overwriting the cause" do
    begin
      begin
        begin
          begin
            raise "Error 1"
          rescue => e1
            raise "Error 2"
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
  end

  it "re-raises a previously rescued exception with overwriting the cause when it's explicitly specified with :cause option" do
    e4 = RuntimeError.new("Error 4")

    begin
      begin
        begin
          begin
            raise "Error 1"
          rescue => e1
            raise "Error 2"
          end
        rescue => e2
          raise "Error 3"
        end
      rescue
        e2.cause.should == e1
        raise e2, cause: e4
      end
    rescue => e
      e.cause.should == e4
    end
  end

  it "re-raises a previously rescued exception without overwriting the cause when it's explicitly specified with :cause option and has nil value" do
    begin
      begin
        begin
          begin
            raise "Error 1"
          rescue => e1
            raise "Error 2"
          end
        rescue => e2
          raise "Error 3"
        end
      rescue
        e2.cause.should == e1
        raise e2, cause: nil
      end
    rescue => e
      e.cause.should == e1
    end
  end

  it "re-raises a previously rescued exception without setting a cause implicitly" do
    begin
      begin
        raise "Error 1"
      rescue => e1
        raise
      end
    rescue => e
      e.should == e1
      e.cause.should == nil
    end
  end

  it "re-raises a previously rescued exception that has a cause without setting a cause implicitly" do
    begin
      begin
        raise "Error 1"
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
  end
end

describe "Kernel#raise" do
  it_behaves_like :kernel_raise, :raise, Kernel
end

describe "Kernel.raise" do
  it "needs to be reviewed for spec completeness"
end
