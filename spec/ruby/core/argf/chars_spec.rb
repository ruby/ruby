require_relative '../../spec_helper'
require_relative 'shared/each_char'

ruby_version_is ''...'3.0' do
  describe "ARGF.chars" do
    before :each do
      @verbose, $VERBOSE = $VERBOSE, nil
    end

    after :each do
      $VERBOSE = @verbose
    end

    it_behaves_like :argf_each_char, :chars
  end
end
