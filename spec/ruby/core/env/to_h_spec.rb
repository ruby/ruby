require_relative '../../spec_helper'
require_relative 'shared/to_hash'

describe "ENV.to_hash" do
  it_behaves_like :env_to_hash, :to_h

  ruby_version_is "2.6" do
    it "converts [key, value] pairs returned by the block to a hash" do
      orig = ENV.to_hash
      begin
        ENV.replace "a" => "b", "c" => "d"
        i = 0
        ENV.to_h {|k, v| [k.to_sym, v.upcase]}.should == {a:"B", c:"D"}
      ensure
        ENV.replace orig
      end
    end
  end
end
