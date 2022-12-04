require_relative '../../spec_helper'

describe "Exception#full_message" do
  it "returns formatted string of exception using the same format that is used to print an uncaught exceptions to stderr" do
    e = RuntimeError.new("Some runtime error")
    e.set_backtrace(["a.rb:1", "b.rb:2"])

    full_message = e.full_message
    full_message.should include "RuntimeError"
    full_message.should include "Some runtime error"
    full_message.should include "a.rb:1"
    full_message.should include "b.rb:2"
  end

  it "supports :highlight option and adds escape sequences to highlight some strings" do
    e = RuntimeError.new("Some runtime error")

    full_message = e.full_message(highlight: true, order: :top).lines
    full_message[0].should.end_with? "\e[1mSome runtime error (\e[1;4mRuntimeError\e[m\e[1m)\e[m\n"

    full_message = e.full_message(highlight: true, order: :bottom).lines
    full_message[0].should == "\e[1mTraceback\e[m (most recent call last):\n"
    full_message[-1].should.end_with? "\e[1mSome runtime error (\e[1;4mRuntimeError\e[m\e[1m)\e[m\n"

    full_message = e.full_message(highlight: false, order: :top).lines
    full_message[0].should.end_with? "Some runtime error (RuntimeError)\n"

    full_message = e.full_message(highlight: false, order: :bottom).lines
    full_message[0].should == "Traceback (most recent call last):\n"
    full_message[-1].should.end_with? "Some runtime error (RuntimeError)\n"
  end

  it "supports :order option and places the error message and the backtrace at the top or the bottom" do
    e = RuntimeError.new("Some runtime error")
    e.set_backtrace(["a.rb:1", "b.rb:2"])

    e.full_message(order: :top,    highlight: false).should =~ /a.rb:1.*b.rb:2/m
    e.full_message(order: :bottom, highlight: false).should =~ /b.rb:2.*a.rb:1/m
  end

  it "shows the caller if the exception has no backtrace" do
    e = RuntimeError.new("Some runtime error")
    e.backtrace.should == nil
    full_message = e.full_message(highlight: false, order: :top).lines
    full_message[0].should.start_with?("#{__FILE__}:#{__LINE__-1}:in `")
    full_message[0].should.end_with?("': Some runtime error (RuntimeError)\n")
  end

  it "shows the exception class at the end of the first line of the message when the message contains multiple lines" do
    begin
      line = __LINE__; raise "first line\nsecond line"
    rescue => e
      full_message = e.full_message(highlight: false, order: :top).lines
      full_message[0].should.start_with?("#{__FILE__}:#{line}:in `")
      full_message[0].should.end_with?(": first line (RuntimeError)\n")
      full_message[1].should == "second line\n"
    end
  end

  it "highlights the entire message when the message contains multiple lines" do
    begin
      line = __LINE__; raise "first line\nsecond line\nthird line"
    rescue => e
      full_message = e.full_message(highlight: true, order: :top).lines
      full_message[0].should.start_with?("#{__FILE__}:#{line}:in `")
      full_message[0].should.end_with?(": \e[1mfirst line (\e[1;4mRuntimeError\e[m\e[1m)\e[m\n")
      full_message[1].should == "\e[1msecond line\e[m\n"
      full_message[2].should == "\e[1mthird line\e[m\n"
    end
  end

  it "contains cause of exception" do
    begin
      begin
        raise 'the cause'
      rescue
        raise 'main exception'
      end
    rescue => e
      exception = e
    end

    exception.full_message.should include "main exception"
    exception.full_message.should include "the cause"
  end

  it 'contains all the chain of exceptions' do
    begin
      begin
        begin
          raise 'origin exception'
        rescue
          raise 'intermediate exception'
        end
      rescue
        raise 'last exception'
      end
    rescue => e
      exception = e
    end

    exception.full_message.should include "last exception"
    exception.full_message.should include "intermediate exception"
    exception.full_message.should include "origin exception"
  end
end
