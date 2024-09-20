require_relative 'spec_helper'

load_extension("exception")

describe "C-API Exception function" do
  before :each do
    @s = CApiExceptionSpecs.new
  end

  describe "rb_exc_new" do
    it "creates an exception from a C string and length" do
      @s.rb_exc_new('foo').to_s.should == 'foo'
    end
  end

  describe "rb_exc_new2" do
    it "creates an exception from a C string" do
      @s.rb_exc_new2('foo').to_s.should == 'foo'
    end
  end

  describe "rb_exc_new3" do
    it "creates an exception from a Ruby string" do
      @s.rb_exc_new3('foo').to_s.should == 'foo'
    end
  end

  describe "rb_exc_raise" do
    it "raises passed exception" do
      runtime_error = RuntimeError.new '42'
      -> { @s.rb_exc_raise(runtime_error) }.should raise_error(RuntimeError, '42')
    end

    it "raises an exception with an empty backtrace" do
      runtime_error = RuntimeError.new '42'
      runtime_error.set_backtrace []
      -> { @s.rb_exc_raise(runtime_error) }.should raise_error(RuntimeError, '42')
    end

    it "sets $! to the raised exception when not rescuing from an another exception" do
      runtime_error = RuntimeError.new '42'
      runtime_error.set_backtrace []
      begin
        @s.rb_exc_raise(runtime_error)
      rescue
        $!.should == runtime_error
      end
    end

    it "sets $! to the raised exception when $! when rescuing from an another exception" do
      runtime_error = RuntimeError.new '42'
      runtime_error.set_backtrace []
      begin
        begin
          raise StandardError
        rescue
          @s.rb_exc_raise(runtime_error)
        end
      rescue
        $!.should == runtime_error
      end
    end
  end

  describe "rb_errinfo" do
    it "is cleared when entering a C method" do
      begin
        raise StandardError
      rescue
        $!.class.should == StandardError
        @s.rb_errinfo().should == nil
      end
    end

    it "does not clear $! in the calling method" do
      begin
        raise StandardError
      rescue
        @s.rb_errinfo()
        $!.class.should == StandardError
      end
    end
  end

  describe "rb_set_errinfo" do
    after :each do
      @s.rb_set_errinfo(nil)
    end

    it "accepts nil" do
      @s.rb_set_errinfo(nil).should be_nil
    end

    it "accepts an Exception instance" do
      @s.rb_set_errinfo(Exception.new).should be_nil
    end

    it "raises a TypeError if the object is not nil or an Exception instance" do
      -> { @s.rb_set_errinfo("error") }.should raise_error(TypeError)
    end
  end

  describe "rb_syserr_new" do
    it "returns system error with default message when passed message is NULL" do
      exception = @s.rb_syserr_new(Errno::ENOENT::Errno, nil)
      exception.class.should == Errno::ENOENT
      exception.message.should include("No such file or directory")
      exception.should.is_a?(SystemCallError)
    end

    it "returns system error with custom message" do
      exception = @s.rb_syserr_new(Errno::ENOENT::Errno, "custom message")

      exception.message.should include("custom message")
      exception.class.should == Errno::ENOENT
      exception.should.is_a?(SystemCallError)
    end
  end

  describe "rb_syserr_new_str" do
    it "returns system error with default message when passed message is nil" do
      exception = @s.rb_syserr_new_str(Errno::ENOENT::Errno, nil)

      exception.message.should include("No such file or directory")
      exception.class.should == Errno::ENOENT
      exception.should.is_a?(SystemCallError)
    end

    it "returns system error with custom message" do
      exception = @s.rb_syserr_new_str(Errno::ENOENT::Errno, "custom message")
      exception.message.should include("custom message")
      exception.class.should == Errno::ENOENT
      exception.should.is_a?(SystemCallError)
    end
  end

  describe "rb_make_exception" do
    it "returns a RuntimeError when given a String argument" do
      e = @s.rb_make_exception(["Message"])
      e.class.should == RuntimeError
      e.message.should == "Message"
    end

    it "returns the exception when given an Exception argument" do
      exc = Exception.new
      e = @s.rb_make_exception([exc])
      e.should == exc
    end

    it "returns the exception with the given class and message" do
      e = @s.rb_make_exception([Exception, "Message"])
      e.class.should == Exception
      e.message.should == "Message"
    end

    it "returns the exception with the given class, message, and backtrace" do
      e = @s.rb_make_exception([Exception, "Message", ["backtrace 1"]])
      e.class.should == Exception
      e.message.should == "Message"
      e.backtrace.should == ["backtrace 1"]
    end

    it "raises a TypeError for incorrect types" do
      -> { @s.rb_make_exception([nil]) }.should raise_error(TypeError)
      -> { @s.rb_make_exception([Object.new]) }.should raise_error(TypeError)
      obj = Object.new
      def obj.exception
        "not exception type"
      end
      -> { @s.rb_make_exception([obj]) }.should raise_error(TypeError)
    end

    it "raises an ArgumentError for too many arguments" do
      -> { @s.rb_make_exception([Exception, "Message", ["backtrace 1"], "extra"])  }.should raise_error(ArgumentError)
    end

    it "returns nil for empty arguments" do
      @s.rb_make_exception([]).should == nil
    end
  end
end
