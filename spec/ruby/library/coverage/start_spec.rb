require_relative '../../spec_helper'
require 'coverage'

describe 'Coverage.start' do
  ruby_version_is '3.2' do
    it "can measure coverage within eval" do
      Coverage.start(lines: true, eval: true)
      eval("Object.new\n"*3, binding, "test.rb", 1)
      Coverage.result["test.rb"].should == {lines: [1, 1, 1]}
    end
  end
end
