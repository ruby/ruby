# encoding: utf-8
# frozen_string_literal: false

begin
  require 'rubygems'
  gem 'minitest'
rescue Gem::LoadError
  # do nothing
end

require 'minitest/unit'
require 'minitest/mock'

MiniTest::Unit.autorun
