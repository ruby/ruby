require_relative '../../spec_helper'

describe "ENV#dup" do
  ruby_version_is "3.1" do
    it "raises TypeError" do
      -> {
        ENV.dup
      }.should raise_error(TypeError, /Cannot dup ENV, use ENV.to_h to get a copy of ENV as a hash/)
    end
  end
end
