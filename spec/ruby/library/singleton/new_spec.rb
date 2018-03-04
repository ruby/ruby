require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Singleton.new" do
  it "is a private method" do
    lambda { SingletonSpecs::NewSpec.new }.should raise_error(NoMethodError)
  end
end
