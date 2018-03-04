require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#!~" do
  class KernelSpecs::NotMatch
    def !~(obj)
      :foo
    end
  end

  it 'calls =~ internally and negates the result' do
    obj = Object.new
    obj.should_receive(:=~).and_return(true)
    (obj !~ :foo).should == false
  end

  it 'can be overridden in subclasses' do
    obj = KernelSpecs::NotMatch.new
    (obj !~ :bar).should == :foo
  end
end
