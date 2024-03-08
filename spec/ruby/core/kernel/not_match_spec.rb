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

  ruby_version_is ""..."3.2" do
    it "returns true if self does not respond to #=~" do
      suppress_warning do
        (Object.new !~ :foo).should == true
      end
    end
  end

  ruby_version_is "3.2" do
    it "raises NoMethodError if self does not respond to #=~" do
      -> { Object.new !~ :foo }.should raise_error(NoMethodError)
    end
  end

  it 'can be overridden in subclasses' do
    obj = KernelSpecs::NotMatch.new
    (obj !~ :bar).should == :foo
  end
end
