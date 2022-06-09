require_relative '../../../spec_helper'
require 'rubygems'

describe "Gem.load_path_insert_index" do
  guard -> { RbConfig::TOPDIR } do
    it "is set for an installed an installed Ruby" do
      Gem.load_path_insert_index.should be_kind_of Integer
    end
  end
end
