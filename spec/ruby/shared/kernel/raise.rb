describe :kernel_raise, shared: true do
  before :each do
    ScratchPad.clear
  end

  it "aborts execution" do
    -> do
      @object.raise Exception, "abort"
      ScratchPad.record :no_abort
    end.should raise_error(Exception, "abort")

    ScratchPad.recorded.should be_nil
  end

  it "raises RuntimeError if no exception class is given" do
    -> { @object.raise }.should raise_error(RuntimeError, "")
  end

  it "raises a given Exception instance" do
    error = RuntimeError.new
    -> { @object.raise(error) }.should raise_error(error)
  end

  it "raises a RuntimeError if string given" do
    -> { @object.raise("a bad thing") }.should raise_error(RuntimeError)
  end

  it "raises a TypeError when passed a non-Exception object" do
    -> { @object.raise(Object.new) }.should raise_error(TypeError)
  end

  it "raises a TypeError when passed true" do
    -> { @object.raise(true) }.should raise_error(TypeError)
  end

  it "raises a TypeError when passed false" do
    -> { @object.raise(false) }.should raise_error(TypeError)
  end

  it "raises a TypeError when passed nil" do
    -> { @object.raise(nil) }.should raise_error(TypeError)
  end

  it "re-raises the previously rescued exception if no exception is specified" do
    -> do
      begin
        @object.raise Exception, "outer"
        ScratchPad.record :no_abort
      rescue
        begin
          @object.raise StandardError, "inner"
        rescue
        end

        @object.raise
        ScratchPad.record :no_reraise
      end
    end.should raise_error(Exception, "outer")

    ScratchPad.recorded.should be_nil
  end

  it "re-raises a previously rescued exception without overwriting the backtrace" do
    begin
      initial_raise_line = __LINE__; @object.raise 'raised'
    rescue => raised
      begin
        raise_again_line = __LINE__; @object.raise raised
      rescue => raised_again
        # This spec is written using #backtrace and matching the line number
        # from the string, as backtrace_locations is a more advanced
        # method that is not always supported by implementations.

        raised_again.backtrace.first.should include("#{__FILE__}:#{initial_raise_line}:")
        raised_again.backtrace.first.should_not include("#{__FILE__}:#{raise_again_line}:")
      end
    end
  end

  it "allows Exception, message, and backtrace parameters" do
    -> do
      @object.raise(ArgumentError, "message", caller)
    end.should raise_error(ArgumentError, "message")
  end
end
