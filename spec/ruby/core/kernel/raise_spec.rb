require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/kernel/raise'

describe "Kernel#raise" do
  it "is a private method" do
    Kernel.private_instance_methods.should include(:raise)
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
    end.should raise_error(Exception, "outer")

    ScratchPad.recorded.should be_nil
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

  it "re-raises a previously rescued exception that doesn't have a cause and isn't a cause of any other exception with setting a cause implicitly" do
    begin
      begin
        raise "Error 1"
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
  end

  it "re-raises a previously rescued exception that doesn't have a cause and is a cause of other exception without setting a cause implicitly" do
    begin
      begin
        raise "Error 1"
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
  end

  it "re-raises a previously rescued exception that doesn't have a cause and is a cause of other exception (that wasn't raised explicitly) without setting a cause implicitly" do
    begin
      begin
        raise "Error 1"
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
  end

  it "re-raises a previously rescued exception that has a cause but isn't a cause of any other exception without setting a cause implicitly" do
    begin
      begin
        raise "Error 1"
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
  end
end

describe "Kernel.raise" do
  it "is a public method" do
    Kernel.singleton_class.should.public_method_defined?(:raise)
  end

  it_behaves_like :kernel_raise, :raise, Kernel
  it_behaves_like :kernel_raise_with_cause, :raise, Kernel
end
