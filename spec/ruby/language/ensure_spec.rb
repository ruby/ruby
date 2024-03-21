require_relative '../spec_helper'
require_relative 'fixtures/ensure'

describe "An ensure block inside a begin block" do
  before :each do
    ScratchPad.record []
  end

  it "is executed when an exception is raised in it's corresponding begin block" do
    -> {
      begin
        ScratchPad << :begin
        raise EnsureSpec::Error
      ensure
        ScratchPad << :ensure
      end
    }.should raise_error(EnsureSpec::Error)

    ScratchPad.recorded.should == [:begin, :ensure]
  end

  it "is executed when an exception is raised and rescued in it's corresponding begin block" do
    begin
      ScratchPad << :begin
      raise "An exception occurred!"
    rescue
      ScratchPad << :rescue
    ensure
      ScratchPad << :ensure
    end

    ScratchPad.recorded.should == [:begin, :rescue, :ensure]
  end

  it "is executed even when a symbol is thrown in it's corresponding begin block" do
    catch(:symbol) do
      begin
        ScratchPad << :begin
        throw(:symbol)
      rescue
        ScratchPad << :rescue
      ensure
        ScratchPad << :ensure
      end
    end

    ScratchPad.recorded.should == [:begin, :ensure]
  end

  it "is executed when nothing is raised or thrown in it's corresponding begin block" do
    begin
      ScratchPad << :begin
    rescue
      ScratchPad << :rescue
    ensure
      ScratchPad << :ensure
    end

    ScratchPad.recorded.should == [:begin, :ensure]
  end

  it "has no return value" do
    begin
      :begin
    ensure
      :ensure
    end.should == :begin
  end

  it "sets exception cause if raises exception in block and in ensure" do
    -> {
      begin
        raise "from block"
      ensure
        raise "from ensure"
      end
    }.should raise_error(RuntimeError, "from ensure") { |e|
      e.cause.message.should == "from block"
    }
  end
end

describe "The value of an ensure expression," do
  it "in no-exception scenarios, is the value of the last statement of the protected body" do
    begin
      v = 1
      eval('x=1') # to prevent opts from triggering
      v
    ensure
      v = 2
    end.should == 1
  end

  it "when an exception is rescued, is the value of the rescuing block" do
    begin
      raise 'foo'
    rescue
      v = 3
    ensure
      v = 2
    end.should == 3
  end
end

describe "An ensure block inside a method" do
  before :each do
    @obj = EnsureSpec::Container.new
  end

  it "is executed when an exception is raised in the method" do
    -> { @obj.raise_in_method_with_ensure }.should raise_error(EnsureSpec::Error)
    @obj.executed.should == [:method, :ensure]
  end

  it "is executed when an exception is raised and rescued in the method" do
    @obj.raise_and_rescue_in_method_with_ensure
    @obj.executed.should == [:method, :rescue, :ensure]
  end

  it "is executed even when a symbol is thrown in the method" do
    catch(:symbol) { @obj.throw_in_method_with_ensure }
    @obj.executed.should == [:method, :ensure]
  end

  it "has no impact on the method's implicit return value" do
    @obj.implicit_return_in_method_with_ensure.should == :method
  end

  it "has an impact on the method's explicit return value" do
    @obj.explicit_return_in_method_with_ensure.should == :ensure
  end

  it "has an impact on the method's explicit return value from rescue if returns explicitly" do
    @obj.explicit_return_in_rescue_and_explicit_return_in_ensure.should == "returned in ensure"
  end

  it "has no impact on the method's explicit return value from rescue if returns implicitly" do
    @obj.explicit_return_in_rescue_and_implicit_return_in_ensure.should == "returned in rescue"
  end

  it "suppresses exception raised in method if returns value explicitly" do
    @obj.raise_and_explicit_return_in_ensure.should == "returned in ensure"
  end

  it "suppresses exception raised in rescue if returns value explicitly" do
    @obj.raise_in_rescue_and_explicit_return_in_ensure.should == "returned in ensure"
  end

  it "overrides exception raised in rescue if raises exception itself" do
    -> {
      @obj.raise_in_rescue_and_raise_in_ensure
    }.should raise_error(RuntimeError, "raised in ensure")
  end

  it "suppresses exception raised in method if raises exception itself" do
    -> {
      @obj.raise_in_method_and_raise_in_ensure
    }.should raise_error(RuntimeError, "raised in ensure")
  end
end

describe "An ensure block inside a class" do
  before :each do
    ScratchPad.record []
  end

  it "is executed when an exception is raised" do
    -> {
      eval <<-ruby
        class EnsureInClassExample
          ScratchPad << :class
          raise EnsureSpec::Error
        ensure
          ScratchPad << :ensure
        end
      ruby
    }.should raise_error(EnsureSpec::Error)

    ScratchPad.recorded.should == [:class, :ensure]
  end

  it "is executed when an exception is raised and rescued" do
    eval <<-ruby
      class EnsureInClassExample
        ScratchPad << :class
        raise
      rescue
        ScratchPad << :rescue
      ensure
        ScratchPad << :ensure
      end
    ruby

    ScratchPad.recorded.should == [:class, :rescue, :ensure]
  end

  it "is executed even when a symbol is thrown" do
    catch(:symbol) do
      eval <<-ruby
        class EnsureInClassExample
          ScratchPad << :class
          throw(:symbol)
        rescue
          ScratchPad << :rescue
        ensure
          ScratchPad << :ensure
        end
      ruby
    end

    ScratchPad.recorded.should == [:class, :ensure]
  end

  it "is executed when nothing is raised or thrown" do
    eval <<-ruby
      class EnsureInClassExample
        ScratchPad << :class
      rescue
        ScratchPad << :rescue
      ensure
        ScratchPad << :ensure
      end
    ruby

    ScratchPad.recorded.should == [:class, :ensure]
  end

  it "has no return value" do
    result = eval <<-ruby
      class EnsureInClassExample
        :class
      ensure
        :ensure
      end
    ruby

    result.should == :class
  end
end

describe "An ensure block inside {} block" do
  it "is not allowed" do
    -> {
      eval <<-ruby
        lambda {
          raise
        ensure
        }
      ruby
    }.should raise_error(SyntaxError)
  end
end

describe "An ensure block inside 'do end' block" do
  before :each do
    ScratchPad.record []
  end

  it "is executed when an exception is raised in it's corresponding begin block" do
    -> {
      eval(<<-ruby).call
        lambda do
          ScratchPad << :begin
          raise EnsureSpec::Error
        ensure
          ScratchPad << :ensure
        end
      ruby
    }.should raise_error(EnsureSpec::Error)

    ScratchPad.recorded.should == [:begin, :ensure]
  end

  it "is executed when an exception is raised and rescued in it's corresponding begin block" do
    eval(<<-ruby).call
      lambda do
        ScratchPad << :begin
        raise "An exception occurred!"
      rescue
        ScratchPad << :rescue
      ensure
        ScratchPad << :ensure
      end
    ruby

    ScratchPad.recorded.should == [:begin, :rescue, :ensure]
  end

  it "is executed even when a symbol is thrown in it's corresponding begin block" do
    catch(:symbol) do
      eval(<<-ruby).call
        lambda do
          ScratchPad << :begin
          throw(:symbol)
        rescue
          ScratchPad << :rescue
        ensure
          ScratchPad << :ensure
        end
      ruby
    end

    ScratchPad.recorded.should == [:begin, :ensure]
  end

  it "is executed when nothing is raised or thrown in it's corresponding begin block" do
    eval(<<-ruby).call
      lambda do
        ScratchPad << :begin
      rescue
        ScratchPad << :rescue
      ensure
        ScratchPad << :ensure
      end
    ruby

    ScratchPad.recorded.should == [:begin, :ensure]
  end

  it "has no return value" do
    result = eval(<<-ruby).call
      lambda do
        :begin
      ensure
        :ensure
      end
    ruby

    result.should == :begin
  end

  ruby_version_is "3.4" do
    it "does not introduce extra backtrace entries" do
      def foo
        begin
          raise "oops"
        ensure
          return caller(0, 2)
        end
      end
      line = __LINE__
      foo.should == [
        "#{__FILE__}:#{line-3}:in 'foo'",
        "#{__FILE__}:#{line+1}:in 'block (3 levels) in <top (required)>'"
      ]
    end
  end
end
