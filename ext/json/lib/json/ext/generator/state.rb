# frozen_string_literal: true

module JSON
  module Ext
    module Generator
      class State
        # call-seq: new(opts = {})
        #
        # Instantiates a new State object, configured by _opts_.
        #
        # Argument +opts+, if given, contains a \Hash of options for the generation.
        # See {Generating Options}[#module-JSON-label-Generating+Options].
        def initialize(opts = nil)
          if opts && !opts.empty?
            configure(opts)
          end
        end

        # call-seq: configure(opts)
        #
        # Configure this State instance with the Hash _opts_, and return
        # itself.
        def configure(opts)
          unless opts.is_a?(Hash)
            if opts.respond_to?(:to_hash)
              opts = opts.to_hash
            elsif opts.respond_to?(:to_h)
              opts = opts.to_h
            else
              raise TypeError, "can't convert #{opts.class} into Hash"
            end
          end
          _configure(opts)
        end

        alias_method :merge, :configure

        # call-seq: to_h
        #
        # Returns the configuration instance variables as a hash, that can be
        # passed to the configure method.
        def to_h
          result = {
            indent: indent,
            space: space,
            space_before: space_before,
            object_nl: object_nl,
            array_nl: array_nl,
            as_json: as_json,
            allow_nan: allow_nan?,
            ascii_only: ascii_only?,
            max_nesting: max_nesting,
            script_safe: script_safe?,
            strict: strict?,
            depth: depth,
            buffer_initial_length: buffer_initial_length,
          }

          allow_duplicate_key = allow_duplicate_key?
          unless allow_duplicate_key.nil?
            result[:allow_duplicate_key] = allow_duplicate_key
          end

          instance_variables.each do |iv|
            iv = iv.to_s[1..-1]
            result[iv.to_sym] = self[iv]
          end

          result
        end

        alias_method :to_hash, :to_h

        # call-seq: [](name)
        #
        # Returns the value returned by method +name+.
        def [](name)
          if respond_to?(name)
            __send__(name)
          else
            instance_variable_get("@#{name}") if
              instance_variables.include?("@#{name}".to_sym) # avoid warning
          end
        end

        # call-seq: []=(name, value)
        #
        # Sets the attribute name to value.
        def []=(name, value)
          if respond_to?(name_writer = "#{name}=")
            __send__ name_writer, value
          else
            instance_variable_set "@#{name}", value
          end
        end
      end
    end
  end
end
