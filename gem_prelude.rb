begin
  require 'rubygems'
rescue LoadError => e
  raise unless e.path == 'rubygems'

  warn "`RubyGems' were not loaded."
else
  require 'bundled_gems'
end if defined?(Gem)

if defined?(ErrorHighlight) || defined?(DidYouMean) || defined?(SyntaxSuggest)
  module Ruby::DetailedError # :nodoc:
    @loaded = false

    def self.loaded? = @loaded

    def self.load
      return if @loaded
      @loaded = true

      begin
        require 'error_highlight'
      rescue LoadError
        warn "`error_highlight' was not loaded."
      end if defined?(ErrorHighlight)

      begin
        require 'did_you_mean'
      rescue LoadError
        warn "`did_you_mean' was not loaded."
      end if defined?(DidYouMean)

      begin
        require 'syntax_suggest/core_ext'
      rescue LoadError
        warn "`syntax_suggest' was not loaded."
      end if defined?(SyntaxSuggest)
    end

    def detailed_message(...)
      return super if Ruby::DetailedError.loaded?
      Ruby::DetailedError.load
      # Re-dispatch to pick up the newly prepended methods from the gems
      detailed_message(...)
    end
  end

  Exception.prepend(Ruby::DetailedError)
end
