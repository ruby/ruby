require 'set'

module Docile
  # @api private
  #
  # A proxy object with a primary receiver as well as a secondary
  # fallback receiver.
  #
  # Will attempt to forward all method calls first to the primary receiver,
  # and then to the fallback receiver if the primary does not handle that
  # method.
  #
  # This is useful for implementing DSL evaluation in the context of an object.
  #
  # @see Docile.dsl_eval
  class FallbackContextProxy
    # The set of methods which will **not** be proxied, but instead answered
    # by this object directly.
    NON_PROXIED_METHODS = Set[:__send__, :object_id, :__id__, :==, :equal?,
                              :'!', :'!=', :instance_exec, :instance_variables,
                              :instance_variable_get, :instance_variable_set,
                              :remove_instance_variable]

    # The set of instance variables which are local to this object and hidden.
    # All other instance variables will be copied in and out of this object
    # from the scope in which this proxy was created.
    NON_PROXIED_INSTANCE_VARIABLES = Set[:@__receiver__, :@__fallback__]

    # Undefine all instance methods except those in {NON_PROXIED_METHODS}
    instance_methods.each do |method|
      undef_method(method) unless NON_PROXIED_METHODS.include?(method.to_sym)
    end

    # @param [Object] receiver  the primary proxy target to which all methods
    #                             initially will be forwarded
    # @param [Object] fallback  the fallback proxy target to which any methods
    #                             not handled by `receiver` will be forwarded
    def initialize(receiver, fallback)
      @__receiver__ = receiver
      @__fallback__ = fallback
    end

    # @return [Array<Symbol>]  Instance variable names, excluding
    #                            {NON_PROXIED_INSTANCE_VARIABLES}
    #
    # @note on Ruby 1.8.x, the instance variable names are actually of
    #   type `String`.
    def instance_variables
      # Ruby 1.8.x returns string names, convert to symbols for compatibility
      super.select { |v| !NON_PROXIED_INSTANCE_VARIABLES.include?(v.to_sym) }
    end

    # Proxy all methods, excluding {NON_PROXIED_METHODS}, first to `receiver`
    # and then to `fallback` if not found.
    def method_missing(method, *args, &block)
      if @__receiver__.respond_to?(method.to_sym)
        @__receiver__.__send__(method.to_sym, *args, &block)
      else
        @__fallback__.__send__(method.to_sym, *args, &block)
      end
    end
  end
end
