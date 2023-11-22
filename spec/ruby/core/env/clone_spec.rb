require_relative '../../spec_helper'

describe "ENV#clone" do
  it "raises ArgumentError when keyword argument 'freeze' is neither nil nor boolean" do
    -> {
      ENV.clone(freeze: 1)
    }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError when keyword argument is not 'freeze'" do
    -> {
      ENV.clone(foo: nil)
    }.should raise_error(ArgumentError)
  end

  ruby_version_is "3.2" do
    it "raises TypeError" do
      -> {
        ENV.clone
      }.should raise_error(TypeError, /Cannot clone ENV, use ENV.to_h to get a copy of ENV as a hash/)
    end
  end
end
