begin
  require 'rubygems'
rescue LoadError => e
  raise unless e.path == 'rubygems'

  warn "`RubyGems' were not loaded."
else
  require 'bundled_gems'
end if defined?(Gem)

if defined?(ErrorHighlight) || defined?(DidYouMean) || defined?(SyntaxSuggest)
  # Replace empty modules with autoload entries for lazy loading.
  # Direct constant access (e.g. DidYouMean::SpellChecker) triggers
  # autoload transparently; error display uses the hook below.
  if defined?(ErrorHighlight)
    Object.send(:remove_const, :ErrorHighlight)
    autoload :ErrorHighlight, 'error_highlight'
  end
  if defined?(DidYouMean)
    Object.send(:remove_const, :DidYouMean)
    autoload :DidYouMean, 'did_you_mean'
  end
  if defined?(SyntaxSuggest)
    Object.send(:remove_const, :SyntaxSuggest)
    autoload :SyntaxSuggest, 'syntax_suggest'
  end

  module Exception::DetailedMessage # :nodoc:
    @require = Kernel.instance_method(:require)

    def detailed_message(...)
      gem_above = self.class.instance_method(:detailed_message).owner != Exception::DetailedMessage

      req = Exception::DetailedMessage.instance_variable_get(:@require)
      begin; req.bind_call(self, 'error_highlight'); rescue LoadError; end
      begin; req.bind_call(self, 'did_you_mean'); rescue LoadError; end
      begin; req.bind_call(self, 'syntax_suggest'); rescue LoadError; end

      Exception::DetailedMessage.remove_method(:detailed_message)
      gem_above ? super : detailed_message(...)
    end
  end
  Exception.prepend(Exception::DetailedMessage)
end
