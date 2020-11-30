# -*- encoding: utf-8 -*-
ruby_version_is ""..."3.0" do
  require_relative '../../spec_helper'
  require_relative 'fixtures/classes'
  require_relative 'shared/chars'

  describe "IO#chars" do
    it_behaves_like :io_chars, :chars
  end

  describe "IO#chars" do
    it_behaves_like :io_chars_empty, :chars
  end
end
