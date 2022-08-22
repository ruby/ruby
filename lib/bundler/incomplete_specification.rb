# frozen_string_literal: true

module Bundler
  class IncompleteSpecification
    attr_reader :name, :platform

    def initialize(name, platform)
      @name = name
      @platform = platform
    end
  end
end
