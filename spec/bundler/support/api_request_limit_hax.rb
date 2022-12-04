# frozen_string_literal: true

if ENV["BUNDLER_SPEC_API_REQUEST_LIMIT"]
  require_relative "path"
  require "bundler/source"
  require "bundler/source/rubygems"

  module Bundler
    class Source
      class Rubygems < Source
        remove_const :API_REQUEST_LIMIT
        API_REQUEST_LIMIT = ENV["BUNDLER_SPEC_API_REQUEST_LIMIT"].to_i
      end
    end
  end
end
