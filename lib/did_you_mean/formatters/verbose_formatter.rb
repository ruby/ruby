# frozen-string-literal: true

module DidYouMean
  # The +DidYouMean::VerboseFormatter+ uses extra empty lines to make the
  # suggestion stand out more in the error message.
  #
  # In order to activate the verbose formatter,
  #
  # @example
  #
  #   OBject
  #   # => NameError: uninitialized constant OBject
  #   #    Did you mean?  Object
  #
  #   require 'did_you_mean/verbose'
  #
  #   OBject
  #   # => NameError: uninitialized constant OBject
  #   #
  #   #        Did you mean? Object
  #   #
  #
  class VerboseFormatter

    # Returns a human readable string that contains +corrections+. This
    # formatter is designed to be less verbose to not take too much screen
    # space while being helpful enough to the user.
    #
    # @example
    #
    #   formatter = DidYouMean::PlainFormatter.new
    #
    #   puts formatter.message_for(["methods", "method"])
    #
    #
    #       Did you mean? methods
    #                     method
    #
    #   # => nil
    #
    def message_for(corrections)
      return "" if corrections.empty?

      output = "\n\n    Did you mean? ".dup
      output << corrections.join("\n                  ")
      output << "\n "
    end
  end
end
