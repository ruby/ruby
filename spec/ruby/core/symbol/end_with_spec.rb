# -*- encoding: utf-8 -*-

require_relative '../../spec_helper'
require_relative '../../shared/string/end_with'

ruby_version_is "2.7" do
  describe "Symbol#end_with?" do
    it_behaves_like :end_with, :to_sym
  end
end
