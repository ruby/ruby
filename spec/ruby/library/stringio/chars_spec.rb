require_relative '../../spec_helper'
require 'stringio'
require_relative 'shared/each_char'

ruby_version_is ''...'3.0' do
  describe "StringIO#chars" do
    before :each do
      @verbose, $VERBOSE = $VERBOSE, nil
    end

    after :each do
      $VERBOSE = @verbose
    end

    it_behaves_like :stringio_each_char, :chars
  end

  describe "StringIO#chars when self is not readable" do
    before :each do
      @verbose, $VERBOSE = $VERBOSE, nil
    end

    after :each do
      $VERBOSE = @verbose
    end

    it_behaves_like :stringio_each_char_not_readable, :chars
  end
end
