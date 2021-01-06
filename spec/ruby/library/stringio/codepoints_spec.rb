# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/codepoints'

ruby_version_is ''...'3.0' do
  # See redmine #1667
  describe "StringIO#codepoints" do
    before :each do
      @verbose, $VERBOSE = $VERBOSE, nil
    end

    after :each do
      $VERBOSE = @verbose
    end

    it_behaves_like :stringio_codepoints, :codepoints
  end
end
