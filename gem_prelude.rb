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
  end

  module Exception::DetailedMessage # :nodoc:
    def detailed_message(...)
      # Check if any gem has already prepended detailed_message
      # above us in the MRO (e.g. loaded via -r flag).
      gem_already_above = self.class.ancestors.take_while { |mod|
        mod != Exception::DetailedMessage
      }.any? { |mod| mod.method_defined?(:detailed_message, false) }

      if defined?(Ruby::DetailedError)
        Ruby::DetailedError.load
      end
      Exception::DetailedMessage.remove_method(:detailed_message)

      if gem_already_above
        # Gems already ran their detailed_message (they called
        # super to reach us). Just forward to Exception.
        super
      else
        # Gems were just loaded. Re-dispatch so their
        # newly-prepended methods run.
        detailed_message(...)
      end
    end
  end
  Exception.prepend(Exception::DetailedMessage)
end
