# frozen_string_literal: true
module Bundler
  if defined? ::Deprecate
    Deprecate = ::Deprecate
  elsif defined? Gem::Deprecate
    Deprecate = Gem::Deprecate
  else
    class Deprecate; end
  end

  unless Deprecate.respond_to?(:skip_during)
    def Deprecate.skip_during
      original = skip
      self.skip = true
      yield
    ensure
      self.skip = original
    end
  end

  unless Deprecate.respond_to?(:skip)
    def Deprecate.skip
      @skip
    end
  end

  unless Deprecate.respond_to?(:skip=)
    def Deprecate.skip=(skip)
      @skip = skip
    end
  end
end
