require_relative 'spec_helper'
require_relative 'shared/to_hash'

describe "ENV.except" do
  before do
    @orig_hash = ENV.to_hash
  end

  after do
    ENV.replace @orig_hash
  end

  # Testing the method without arguments is covered via
  it_behaves_like :env_to_hash, :except

  it "returns a hash without the requested subset" do
    ENV.clear

    ENV['one'] = '1'
    ENV['two'] = '2'
    ENV['three'] = '3'

    ENV.except('one', 'three').should == { 'two' => '2' }
  end

  it "ignores keys not present in the original hash" do
    ENV.clear

    ENV['one'] = '1'
    ENV['two'] = '2'

    ENV.except('one', 'three').should == { 'two' => '2' }
  end
end
