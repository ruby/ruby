# frozen_string_literal: true

module JSON
  module Ext
    module Generator
      class State
        # call-seq: new(opts = {})
        #
        # Instantiates a new State object, configured by _opts_.
        #
        # _opts_ can have the following keys:
        #
        # * *indent*: a string used to indent levels (default: ''),
        # * *space*: a string that is put after, a : or , delimiter (default: ''),
        # * *space_before*: a string that is put before a : pair delimiter (default: ''),
        # * *object_nl*: a string that is put at the end of a JSON object (default: ''),
        # * *array_nl*: a string that is put at the end of a JSON array (default: ''),
        # * *allow_nan*: true if NaN, Infinity, and -Infinity should be
        #   generated, otherwise an exception is thrown, if these values are
        #   encountered. This options defaults to false.
        # * *ascii_only*: true if only ASCII characters should be generated. This
        #   option defaults to false.
        # * *buffer_initial_length*: sets the initial length of the generator's
        #   internal buffer.
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

          self.indent = opts[:indent] if opts.key?(:indent)
          self.space = opts[:space] if opts.key?(:space)
          self.space_before = opts[:space_before] if opts.key?(:space_before)
          self.array_nl = opts[:array_nl] if opts.key?(:array_nl)
          self.object_nl = opts[:object_nl] if opts.key?(:object_nl)
          self.max_nesting = opts[:max_nesting] || 0 if opts.key?(:max_nesting)
          self.depth = opts[:depth] if opts.key?(:depth)
          self.buffer_initial_length = opts[:buffer_initial_length] if opts.key?(:buffer_initial_length)
          self.allow_nan = opts[:allow_nan] if opts.key?(:allow_nan)
          self.ascii_only = opts[:ascii_only] if opts.key?(:ascii_only)

          if opts.key?(:script_safe)
            self.script_safe = opts[:script_safe]
          elsif opts.key?(:escape_slash)
            self.script_safe = opts[:escape_slash]
          end

          self.strict = opts[:strict] if opts[:strict]

          self
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
            allow_nan: allow_nan?,
            ascii_only: ascii_only?,
            max_nesting: max_nesting,
            script_safe: script_safe?,
            strict: strict?,
            depth: depth,
            buffer_initial_length: buffer_initial_length,
          }

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
