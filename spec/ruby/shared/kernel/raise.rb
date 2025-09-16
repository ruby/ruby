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

  it "accepts an exception that implements to_hash" do
    custom_error = Class.new(StandardError) do
      def to_hash
        {}
      end
    end
    error = custom_error.new
    -> { @object.raise(error) }.should raise_error(custom_error)
  end

  it "allows the message parameter to be a hash" do
    data_error = Class.new(StandardError) do
      attr_reader :data
      def initialize(data)
        @data = data
      end
    end

    -> { @object.raise(data_error, {data: 42}) }.should raise_error(data_error) do |ex|
      ex.data.should == {data: 42}
    end
  end

  # https://bugs.ruby-lang.org/issues/8257#note-36
  it "allows extra keyword arguments for compatibility" do
    data_error = Class.new(StandardError) do
      attr_reader :data
      def initialize(data)
        @data = data
      end
    end

    -> { @object.raise(data_error, data: 42) }.should raise_error(data_error) do |ex|
      ex.data.should == {data: 42}
    end
  end

  it "raises RuntimeError if no exception class is given" do
    -> { @object.raise }.should raise_error(RuntimeError, "")
  end

  it "raises a given Exception instance" do
    error = RuntimeError.new
    -> { @object.raise(error) }.should raise_error(error)
  end

  it "raises a RuntimeError if string given" do
    -> { @object.raise("a bad thing") }.should raise_error(RuntimeError, "a bad thing")
  end

  it "passes no arguments to the constructor when given only an exception class" do
    klass = Class.new(Exception) do
      def initialize
      end
    end
    -> { @object.raise(klass) }.should raise_error(klass) { |e| e.message.should == klass.to_s }
  end

  it "raises a TypeError when passed a non-Exception object" do
    -> { @object.raise(Object.new) }.should raise_error(TypeError, "exception class/object expected")
    -> { @object.raise(Object.new, "message") }.should raise_error(TypeError, "exception class/object expected")
    -> { @object.raise(Object.new, "message", []) }.should raise_error(TypeError, "exception class/object expected")
  end

  it "raises a TypeError when passed true" do
    -> { @object.raise(true) }.should raise_error(TypeError, "exception class/object expected")
  end

  it "raises a TypeError when passed false" do
    -> { @object.raise(false) }.should raise_error(TypeError, "exception class/object expected")
  end

  it "raises a TypeError when passed nil" do
    -> { @object.raise(nil) }.should raise_error(TypeError, "exception class/object expected")
  end

  it "raises a TypeError when passed a message and an extra argument" do
    -> { @object.raise("message", {cause: RuntimeError.new()}) }.should raise_error(TypeError, "exception class/object expected")
  end

  it "raises TypeError when passed a non-Exception object but it responds to #exception method that doesn't return an instance of Exception class" do
    e = Object.new
    def e.exception
      Array
    end

    -> {
      @object.raise e
    }.should raise_error(TypeError, "exception object expected")
  end

  it "re-raises a previously rescued exception without overwriting the backtrace" do
    exception = nil

    begin
      raise "raised"
    rescue => exception
      # Ignore.
    end

    backtrace = exception.backtrace

    begin
      raised_exception = @object.raise(exception)
    rescue => raised_exception
      # Ignore.
    end

    raised_exception.backtrace.should == backtrace
    raised_exception.should == exception
  end

  it "allows Exception, message, and backtrace parameters" do
    -> do
      @object.raise(ArgumentError, "message", caller)
    end.should raise_error(ArgumentError, "message")
  end

  ruby_version_is "3.4" do
    locations = caller_locations(1, 2)
    it "allows Exception, message, and backtrace_locations parameters" do
      -> do
        @object.raise(ArgumentError, "message", locations)
      end.should raise_error(ArgumentError, "message") { |error|
        error.backtrace_locations.map(&:to_s).should == locations.map(&:to_s)
      }
    end
  end

  ruby_version_is "3.5" do
    it "allows cause keyword argument" do
      cause = StandardError.new("original error")
      result = nil

      -> do
        @object.raise("new error", cause: cause)
      end.should raise_error(RuntimeError, "new error") do |error|
        error.cause.should == cause
      end
    end

    it "raises an ArgumentError when only cause is given" do
      cause = StandardError.new("cause")
      -> do
        @object.raise(cause: cause)
      end.should raise_error(ArgumentError, "only cause is given with no arguments")
    end

    it "raises an ArgumentError when only cause is given and is nil" do
      -> do
        @object.raise(cause: nil)
      end.should raise_error(ArgumentError, "only cause is given with no arguments")
    end

    it "raises a TypeError when given cause is not an instance of Exception" do
      cause = Object.new
      -> do
        @object.raise("message", cause: cause)
      end.should raise_error(TypeError, "exception object expected")
    end

    it "doesn't set given cause when it equals the raised exception" do
      cause = StandardError.new("cause")
      result = nil

      -> do
        @object.raise(cause, cause: cause)
      end.should raise_error(StandardError, "cause") do |error|
        error.should == cause
        error.cause.should == nil
      end
    end

    it "accepts cause equal an exception" do
      error = RuntimeError.new("message")
      result = nil

      -> do
        @object.raise(error, cause: error)
      end.should raise_error(RuntimeError, "message") do |error|
        error.cause.should == nil
      end
    end

    it "rejects circular causes" do
      -> {
        begin
          raise "Error 1"
        rescue => error1
          begin
            raise "Error 2"
          rescue => error2
            begin
              raise "Error 3"
            rescue => error3
              @object.raise(error1, cause: error3)
            end
          end
        end
      }.should raise_error(ArgumentError, "circular causes")
    end

    it "supports exception class with message and cause" do
      cause = StandardError.new("cause message")
      result = nil

      -> do
        @object.raise(ArgumentError, "argument error message", cause: cause)
      end.should raise_error(ArgumentError, "argument error message") do |error|
        error.should be_kind_of(ArgumentError)
        error.message.should == "argument error message"
        error.cause.should == cause
      end
    end

    it "supports exception class with message, backtrace and cause" do
      cause = StandardError.new("cause message")
      backtrace = ["line1", "line2"]
      result = nil

      -> do
        @object.raise(ArgumentError, "argument error message", backtrace, cause: cause)
      end.should raise_error(ArgumentError, "argument error message") do |error|
        error.should be_kind_of(ArgumentError)
        error.message.should == "argument error message"
        error.cause.should == cause
        error.backtrace.should == backtrace
      end
    end

    it "supports automatic cause chaining" do
      -> do
        begin
          raise "first error"
        rescue
          # No explicit cause - should chain automatically:
          @object.raise("second error")
        end
      end.should raise_error(RuntimeError, "second error") do |error|
        error.cause.should be_kind_of(RuntimeError)
        error.cause.message.should == "first error"
      end
    end

    it "supports cause: nil to prevent automatic cause chaining" do
      -> do
        begin
          raise "first error"
        rescue
          # Explicit nil prevents chaining:
          @object.raise("second error", cause: nil)
        end
      end.should raise_error(RuntimeError, "second error") do |error|
        error.cause.should == nil
      end
    end
  end
end

describe :kernel_raise_across_contexts, shared: true do
  ruby_version_is "3.5" do
    describe "with cause keyword argument" do
      it "uses the cause from the calling context" do
        original_cause = nil
        result = nil

        # We have no cause ($!) and we don't specify one explicitly either:
        @object.raise("second error") do |&block|
          begin
            begin
              raise "first error"
            rescue => original_cause
              # We have a cause here ($!) but we should ignore it:
              block.call
            end
          rescue => result
            # Ignore.
          end
        end

        result.should be_kind_of(RuntimeError)
        result.message.should == "second error"
        result.cause.should == nil
      end

      it "accepts a cause keyword argument that overrides the last exception" do
        original_cause = nil
        override_cause = StandardError.new("override cause")
        result = nil

        begin
          raise "outer error"
        rescue
          # We have an existing cause, but we want to override it:
          @object.raise("second error", cause: override_cause) do |&block|
            begin
              begin
                raise "first error"
              rescue => original_cause
                # We also have an existing cause here:
                block.call
              end
            rescue => result
              # Ignore.
            end
          end
        end

        result.should be_kind_of(RuntimeError)
        result.message.should == "second error"
        result.cause.should == override_cause
      end

      it "supports automatic cause chaining from calling context" do
        result = nil

        @object.raise("new error") do |&block|
          begin
            begin
              raise "original error"
            rescue
              block.call # Let the context yield/sleep
            end
          rescue => result
            # Ignore.
          end
        end

        result.should be_kind_of(RuntimeError)
        result.message.should == "new error"
        # Calling context has no current exception:
        result.cause.should == nil
      end

      it "supports explicit cause: nil to prevent cause chaining" do
        result = nil

        begin
          raise "calling context error"
        rescue
          @object.raise("new error", cause: nil) do |&block|
            begin
              begin
                raise "target context error"
              rescue
                block.call # Let the context yield/sleep
              end
            rescue => result
              # Ignore.
            end
          end

          result.should be_kind_of(RuntimeError)
          result.message.should == "new error"
          result.cause.should == nil
        end
      end

      it "raises TypeError when cause is not an Exception" do
        -> {
          @object.raise("error", cause: "not an exception") do |&block|
            begin
              block.call # Let the context yield/sleep
            rescue
              # Ignore - we expect the TypeError to be raised in the calling context
            end
          end
        }.should raise_error(TypeError, "exception object expected")
      end

      it "raises ArgumentError when only cause is given with no arguments" do
        -> {
          @object.raise(cause: StandardError.new("cause")) do |&block|
            begin
              block.call # Let the context yield/sleep
            rescue
              # Ignore - we expect the ArgumentError to be raised in the calling context
            end
          end
        }.should raise_error(ArgumentError, "only cause is given with no arguments")
      end
    end
  end
end
