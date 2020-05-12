require_relative "../spell_checker"

module DidYouMean
  class MethodNameChecker
    attr_reader :method_name, :receiver

    NAMES_TO_EXCLUDE = { NilClass => nil.methods }
    NAMES_TO_EXCLUDE.default = []

    # +MethodNameChecker::RB_RESERVED_WORDS+ is the list of reserved words in
    # Ruby that take an argument. Unlike
    # +VariableNameChecker::RB_RESERVED_WORDS+, these reserved words require
    # an argument, and a +NoMethodError+ is raised due to the presence of the
    # argument.
    #
    # The +MethodNameChecker+ will use this list to suggest a reversed word if
    # a +NoMethodError+ is raised and found closest matches.
    #
    # Also see +VariableNameChecker::RB_RESERVED_WORDS+.
    RB_RESERVED_WORDS = %i(
      alias
      case
      def
      defined?
      elsif
      end
      ensure
      for
      rescue
      super
      undef
      unless
      until
      when
      while
      yield
    )

    def initialize(exception)
      @method_name  = exception.name
      @receiver     = exception.receiver
      @private_call = exception.respond_to?(:private_call?) ? exception.private_call? : false
    end

    def corrections
      @corrections ||= SpellChecker.new(dictionary: RB_RESERVED_WORDS + method_names).correct(method_name) - names_to_exclude
    end

    def method_names
      if Object === receiver
        method_names = receiver.methods + receiver.singleton_methods
        method_names += receiver.private_methods if @private_call
        method_names.uniq!
        method_names
      else
        []
      end
    end

    def names_to_exclude
      Object === receiver ? NAMES_TO_EXCLUDE[receiver.class] : []
    end
  end
end
