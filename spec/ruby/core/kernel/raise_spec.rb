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
end

describe "Kernel#raise" do
  it_behaves_like :kernel_raise, :raise, Kernel
end

describe "Kernel.raise" do
  it "needs to be reviewed for spec completeness"
end
