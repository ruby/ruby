# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/chars'

ruby_version_is ''...'2.8' do
  describe "IO#chars" do
    it_behaves_like :io_chars, :chars
  end

  describe "IO#chars" do
    it_behaves_like :io_chars_empty, :chars
  end
end
