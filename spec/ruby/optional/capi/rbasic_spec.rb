require_relative 'spec_helper'
require_relative 'shared/rbasic'
load_extension("rbasic")
return if /mswin/ =~ RUBY_PLATFORM && ENV.key?('GITHUB_ACTIONS') # not working from the beginning
load_extension("data")
load_extension("array")

describe "RBasic support for regular objects" do
  before :all do
    @specs = CApiRBasicSpecs.new
    @data = -> { [Object.new, Object.new] }
  end
  it_should_behave_like :rbasic
end

describe "RBasic support for RData" do
  before :all do
    @specs = CApiRBasicRDataSpecs.new
    @wrapping = CApiWrappedStructSpecs.new
    @data = -> { [@wrapping.wrap_struct(1024), @wrapping.wrap_struct(1025)] }
  end
  it_should_behave_like :rbasic
end
