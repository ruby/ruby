require_relative '../spec_helper'
require_relative 'fixtures/rescue'

class SpecificExampleException < StandardError
end
class OtherCustomException < StandardError
end
class ArbitraryException < StandardError
end

exception_list = [SpecificExampleException, ArbitraryException]

describe "The rescue keyword" do
  before :each do
    ScratchPad.record []
  end

  it "can be used to handle a specific exception" do
    begin
      raise SpecificExampleException, "Raising this to be handled below"
    rescue SpecificExampleException
      :caught
    end.should == :caught
  end

  it "can capture the raised exception in a local variable" do
    begin
      raise SpecificExampleException, "some text"
    rescue SpecificExampleException => e
      e.message.should == "some text"
    end
  end

  it "returns value from `rescue` if an exception was raised" do
    begin
      raise
    rescue
      :caught
    end.should == :caught
  end

  it "returns value from `else` section if no exceptions were raised" do
    result = begin
      :begin
    rescue
      :rescue
    else
      :else
    ensure
      :ensure
    end

    result.should == :else
  end

  it "can rescue multiple raised exceptions with a single rescue block" do
    [->{raise ArbitraryException}, ->{raise SpecificExampleException}].map do |block|
      begin
        block.call
      rescue SpecificExampleException, ArbitraryException
        :caught
      end
    end.should == [:caught, :caught]
  end

  it "can rescue a splatted list of exceptions" do
    caught_it = false
    begin
      raise SpecificExampleException, "not important"
    rescue *exception_list
      caught_it = true
    end
    caught_it.should be_true
    caught = []
    [->{raise ArbitraryException}, ->{raise SpecificExampleException}].each do |block|
      begin
        block.call
      rescue *exception_list
        caught << $!
      end
    end
    caught.size.should == 2
    exception_list.each do |exception_class|
      caught.map{|e| e.class}.should include(exception_class)
    end
  end

  it "can combine a splatted list of exceptions with a literal list of exceptions" do
    caught_it = false
    begin
      raise SpecificExampleException, "not important"
    rescue ArbitraryException, *exception_list
      caught_it = true
    end
    caught_it.should be_true
    caught = []
    [->{raise ArbitraryException}, ->{raise SpecificExampleException}].each do |block|
      begin
        block.call
      rescue ArbitraryException, *exception_list
        caught << $!
      end
    end
    caught.size.should == 2
    exception_list.each do |exception_class|
      caught.map{|e| e.class}.should include(exception_class)
    end
  end

  it "will only rescue the specified exceptions when doing a splat rescue" do
    -> do
      begin
        raise OtherCustomException, "not rescued!"
      rescue *exception_list
      end
    end.should raise_error(OtherCustomException)
  end

  it "can rescue different types of exceptions in different ways" do
    begin
      raise Exception
    rescue RuntimeError
    rescue StandardError
    rescue Exception
      ScratchPad << :exception
    end

    ScratchPad.recorded.should == [:exception]
  end

  it "rescues exception within the first suitable section in order of declaration" do
    begin
      raise StandardError
    rescue RuntimeError
      ScratchPad << :runtime_error
    rescue StandardError
      ScratchPad << :standard_error
    rescue Exception
      ScratchPad << :exception
    end

    ScratchPad.recorded.should == [:standard_error]
  end

  it "rescues the exception in the deepest rescue block declared to handle the appropriate exception type" do
    begin
      begin
        RescueSpecs.raise_standard_error
      rescue ArgumentError
      end
    rescue StandardError => e
      e.backtrace.first.should include ":in `raise_standard_error'"
    else
      fail("exception wasn't handled by the correct rescue block")
    end
  end

  it "will execute an else block only if no exceptions were raised" do
    result = begin
      ScratchPad << :one
    rescue
      ScratchPad << :does_not_run
    else
      ScratchPad << :two
      :val
    end
    result.should == :val
    ScratchPad.recorded.should == [:one, :two]
  end

  it "will execute an else block with ensure only if no exceptions were raised" do
    result = begin
      ScratchPad << :one
    rescue
      ScratchPad << :does_not_run
    else
      ScratchPad << :two
      :val
    ensure
      ScratchPad << :ensure
      :ensure_val
    end
    result.should == :val
    ScratchPad.recorded.should == [:one, :two, :ensure]
  end

  it "will execute an else block only if no exceptions were raised in a method" do
    result = RescueSpecs.begin_else(false)
    result.should == :val
    ScratchPad.recorded.should == [:one, :else_ran]
  end

  it "will execute an else block with ensure only if no exceptions were raised in a method" do
    result = RescueSpecs.begin_else_ensure(false)
    result.should == :val
    ScratchPad.recorded.should == [:one, :else_ran, :ensure_ran]
  end

  it "will execute an else block but use the outer scope return value in a method" do
    result = RescueSpecs.begin_else_return(false)
    result.should == :return_val
    ScratchPad.recorded.should == [:one, :else_ran, :outside_begin]
  end

  it "will execute an else block with ensure but use the outer scope return value in a method" do
    result = RescueSpecs.begin_else_return_ensure(false)
    result.should == :return_val
    ScratchPad.recorded.should == [:one, :else_ran, :ensure_ran, :outside_begin]
  end

  ruby_version_is ''...'2.6' do
    it "will execute an else block even without rescue and ensure" do
      -> {
        eval <<-ruby
          begin
            ScratchPad << :begin
          else
            ScratchPad << :else
          end
        ruby
      }.should complain(/else without rescue is useless/)

      ScratchPad.recorded.should == [:begin, :else]
    end
  end

  ruby_version_is '2.6' do
    it "raises SyntaxError when else is used without rescue and ensure" do
      -> {
        eval <<-ruby
          begin
            ScratchPad << :begin
          else
            ScratchPad << :else
          end
        ruby
      }.should raise_error(SyntaxError, /else without rescue is useless/)
    end
  end

  it "will not execute an else block if an exception was raised" do
    result = begin
      ScratchPad << :one
      raise "an error occurred"
    rescue
      ScratchPad << :two
      :val
    else
      ScratchPad << :does_not_run
    end
    result.should == :val
    ScratchPad.recorded.should == [:one, :two]
  end

  it "will not execute an else block with ensure if an exception was raised" do
    result = begin
      ScratchPad << :one
      raise "an error occurred"
    rescue
      ScratchPad << :two
      :val
    else
      ScratchPad << :does_not_run
    ensure
      ScratchPad << :ensure
      :ensure_val
    end
    result.should == :val
    ScratchPad.recorded.should == [:one, :two, :ensure]
  end

  it "will not execute an else block if an exception was raised in a method" do
    result = RescueSpecs.begin_else(true)
    result.should == :rescue_val
    ScratchPad.recorded.should == [:one, :rescue_ran]
  end

  it "will not execute an else block with ensure if an exception was raised in a method" do
    result = RescueSpecs.begin_else_ensure(true)
    result.should == :rescue_val
    ScratchPad.recorded.should == [:one, :rescue_ran, :ensure_ran]
  end

  it "will not execute an else block but use the outer scope return value in a method" do
    result = RescueSpecs.begin_else_return(true)
    result.should == :return_val
    ScratchPad.recorded.should == [:one, :rescue_ran, :outside_begin]
  end

  it "will not execute an else block with ensure but use the outer scope return value in a method" do
    result = RescueSpecs.begin_else_return_ensure(true)
    result.should == :return_val
    ScratchPad.recorded.should == [:one, :rescue_ran, :ensure_ran, :outside_begin]
  end

  it "will not rescue errors raised in an else block in the rescue block above it" do
    -> do
      begin
        ScratchPad << :one
      rescue Exception
        ScratchPad << :does_not_run
      else
        ScratchPad << :two
        raise SpecificExampleException, "an error from else"
      end
    end.should raise_error(SpecificExampleException)
    ScratchPad.recorded.should == [:one, :two]
  end

  it "parses  'a += b rescue c' as 'a += (b rescue c)'" do
    a = 'a'
    c = 'c'
    a += b rescue c
    a.should == 'ac'
  end

  context "without rescue expression" do
    it "will rescue only StandardError and its subclasses" do
      begin
        raise StandardError
      rescue
        ScratchPad << :caught
      end

      ScratchPad.recorded.should == [:caught]
    end

    it "will not rescue exceptions except StandardError" do
      [ Exception.new, NoMemoryError.new, ScriptError.new, SecurityError.new,
        SignalException.new('INT'), SystemExit.new, SystemStackError.new
      ].each do |exception|
        -> {
          begin
            raise exception
          rescue
            ScratchPad << :caught
          end
        }.should raise_error(exception.class)
      end
      ScratchPad.recorded.should == []
    end
  end

  it "uses === to compare against rescued classes" do
    rescuer = Class.new

    def rescuer.===(exception)
      true
    end

    begin
      raise Exception
    rescue rescuer
      rescued = :success
    rescue Exception
      rescued = :failure
    end

    rescued.should == :success
  end

  it "only accepts Module or Class in rescue clauses" do
    rescuer = 42
    -> {
      begin
        raise "error"
      rescue rescuer
      end
    }.should raise_error(TypeError) { |e|
      e.message.should =~ /class or module required for rescue clause/
    }
  end

  it "only accepts Module or Class in splatted rescue clauses" do
    rescuer = [42]
    -> {
      begin
        raise "error"
      rescue *rescuer
      end
    }.should raise_error(TypeError) { |e|
      e.message.should =~ /class or module required for rescue clause/
    }
  end

  it "evaluates rescue expressions only when needed" do
    begin
      ScratchPad << :foo
    rescue -> { ScratchPad << :bar; StandardError }.call
    end

    ScratchPad.recorded.should == [:foo]
  end

  it "suppresses exception from block when raises one from rescue expression" do
    -> {
      begin
        raise "from block"
      rescue (raise "from rescue expression")
      end
    }.should raise_error(RuntimeError, "from rescue expression") do |e|
      e.cause.message.should == "from block"
    end
  end

  it "should splat the handling Error classes" do
    begin
      raise "raise"
    rescue *(RuntimeError) => e
      :expected
    end.should == :expected
  end

  it "allows rescue in class" do
    eval <<-ruby
      class RescueInClassExample
        raise SpecificExampleException
      rescue SpecificExampleException
        ScratchPad << :caught
      end
    ruby

    ScratchPad.recorded.should == [:caught]
  end

  it "does not allow rescue in {} block" do
    -> {
      eval <<-ruby
        lambda {
          raise SpecificExampleException
        rescue SpecificExampleException
          :caught
        }
      ruby
    }.should raise_error(SyntaxError)
  end

  ruby_version_is "2.5" do
    it "allows rescue in 'do end' block" do
      lambda = eval <<-ruby
        lambda do
          raise SpecificExampleException
        rescue SpecificExampleException
          ScratchPad << :caught
        end.call
      ruby

      ScratchPad.recorded.should == [:caught]
    end
  end

  it "allows 'rescue' in method arguments" do
    two = eval '1.+ (raise("Error") rescue 1)'
    two.should == 2
  end

  it "requires the 'rescue' in method arguments to be wrapped in parens" do
    -> { eval '1.+(1 rescue 1)' }.should raise_error(SyntaxError)
    eval('1.+((1 rescue 1))').should == 2
  end

  describe "inline form" do
    it "can be inlined" do
      a = 1/0 rescue 1
      a.should == 1
    end

    it "doesn't except rescue expression" do
      -> {
        eval <<-ruby
          a = 1 rescue RuntimeError 2
        ruby
      }.should raise_error(SyntaxError)
    end

    it "rescues only StandardError and its subclasses" do
      a = raise(StandardError) rescue 1
      a.should == 1

      -> {
        a = raise(Exception) rescue 1
      }.should raise_error(Exception)
    end
  end
end
