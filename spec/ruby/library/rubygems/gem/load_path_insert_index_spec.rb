require_relative '../../../spec_helper'
require 'rubygems'

describe "Gem.load_path_insert_index" do
  guard -> { RbConfig::TOPDIR } do
    it "is set for an installed Ruby" do
      Gem.load_path_insert_index.should.is_a? Integer
    end
  end
end
