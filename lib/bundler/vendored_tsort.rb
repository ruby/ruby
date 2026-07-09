# frozen_string_literal: true

begin
  require "rubygems/vendored_tsort"
rescue LoadError
  require "tsort"
  Gem::TSort = TSort
end
