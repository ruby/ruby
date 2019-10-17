# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/chars'

describe "IO#each_char" do
  it_behaves_like :io_chars, :each_char
end

describe "IO#each_char" do
  it_behaves_like :io_chars_empty, :each_char
end
