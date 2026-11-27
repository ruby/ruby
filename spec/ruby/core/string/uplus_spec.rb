# frozen_string_literal: false
require_relative '../../spec_helper'

describe 'String#+@' do
  it 'returns an unfrozen copy of a frozen String' do
    input  = 'foo'.freeze
    output = +input

    output.should_not.frozen?
    output.should == 'foo'

    output << 'bar'
    output.should == 'foobar'
  end

  it 'returns a mutable String itself' do
    input = String.new("foo")
    output = +input

    output.should.equal?(input)

    input << "bar"
    output.should == "foobar"
  end

  context 'if file has "frozen_string_literal: true" magic comment' do
    it 'returns mutable copy of a literal' do
      ruby_exe(fixture(__FILE__, "freeze_magic_comment.rb")).should == 'mutable'
    end
  end

  context 'if file has "frozen_string_literal: false" magic comment' do
    it 'returns literal string itself' do
      input  = 'foo'
      output = +input

      output.equal?(input).should == true
    end
  end

  context 'if file has no frozen_string_literal magic comment' do
    ruby_version_is ''...'3.4' do
      it 'returns literal string itself' do
        eval(<<~RUBY).should == true
          s = "foo"
          s.equal?(+s)
        RUBY
      end
    end

    ruby_version_is '3.4' do
      it 'returns mutable copy of a literal' do
        eval(<<~RUBY).should == false
          s = "foo"
          s.equal?(+s)
        RUBY
      end
    end
  end
end
