module ::RbConfig
  module Obsolete
  end
  class << Obsolete
    def _warn_
      loc, = caller_locations(2, 1)
      loc = "#{loc.to_s}: " if loc
      warn "#{loc}Use RbConfig instead of obsolete and deprecated Config."
      self
    end

    def const_missing(name)
      _warn_
      ::RbConfig.const_get(name)
    end

    def method_missing(*args, &block)
      _warn_
      rbconfig = ::RbConfig
      result = rbconfig.__send__(*args, &block)
      result = rbconfig if rbconfig.equal?(result)
      result
    end

    def respond_to_missing?(*args, &block)
      _warn_
      ::RbConfig.send(:respond_to_missing?, *args, &block)
    end
  end
end

::Config = ::RbConfig::Obsolete._warn_
=begin
def Object.const_missing(name)
  return super unless name == :Config
  ::RbConfig::Obsolete._warn_
end
=end
