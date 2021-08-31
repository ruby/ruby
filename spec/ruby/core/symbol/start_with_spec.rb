# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/string/start_with'

ruby_version_is "2.7" do
  describe "Symbol#start_with?" do
    it_behaves_like :start_with, :to_sym
  end
end
