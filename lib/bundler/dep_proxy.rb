# frozen_string_literal: true

module Bundler
  class DepProxy
    attr_reader :__platform, :dep

    def initialize(dep, platform)
      @dep = dep
      @__platform = platform
    end

    def hash
      @hash ||= [dep, __platform].hash
    end

    def ==(other)
      return false if other.class != self.class
      dep == other.dep && __platform == other.__platform
    end

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

  private

    def method_missing(*args, &blk)
      @dep.send(*args, &blk)
    end
  end
end
