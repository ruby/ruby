# frozen_string_literal: true

module Bundler
  class DepProxy
    attr_reader :__platform, :dep

    @proxies = {}

    def self.get_proxy(dep, platform)
      @proxies[[dep, platform]] ||= new(dep, platform).freeze
    end

    def initialize(dep, platform)
      @dep = dep
      @__platform = platform
    end

    private_class_method :new

    alias_method :eql?, :==

    def type
      @dep.type
    end

    def name
      @dep.name
    end

    def requirement
      @dep.requirement
    end

    def to_s
      s = name.dup
      s << " (#{requirement})" unless requirement == Gem::Requirement.default
      s << " #{__platform}" unless __platform == Gem::Platform::RUBY
      s
    end

    def dup
      raise NoMethodError.new("DepProxy cannot be duplicated")
    end

    def clone
      raise NoMethodError.new("DepProxy cannot be cloned")
    end

    private

    def method_missing(*args, &blk)
      @dep.send(*args, &blk)
    end
  end
end
