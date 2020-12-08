require_relative '../../spec_helper'
require 'stringio'
require_relative 'shared/each'

ruby_version_is ''...'3.0' do
  describe "StringIO#lines when passed a separator" do
    it_behaves_like :stringio_each_separator, :lines
  end

  describe "StringIO#lines when passed no arguments" do
    it_behaves_like :stringio_each_no_arguments, :lines
  end

  describe "StringIO#lines when self is not readable" do
    it_behaves_like :stringio_each_not_readable, :lines
  end

  describe "StringIO#lines when passed chomp" do
    it_behaves_like :stringio_each_chomp, :lines
  end
end
