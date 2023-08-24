# frozen_string_literal: true

require_relative "visitor"

module Gem::SafeMarshal
  module Visitors
    class ToRuby < Visitor
      def initialize(permitted_classes:, permitted_symbols:, permitted_ivars:)
        @permitted_classes = permitted_classes
        @permitted_symbols = permitted_symbols | permitted_classes | ["E"]
        @permitted_ivars = permitted_ivars

        @objects = []
        @symbols = []
        @class_cache = {}

        @stack = ["root"]
      end

      def inspect # :nodoc:
        format("#<%s permitted_classes: %p permitted_symbols: %p permitted_ivars: %p>",
          self.class, @permitted_classes, @permitted_symbols, @permitted_ivars)
      end

      def visit(target)
        depth = @stack.size
        super
      ensure
        @stack.slice!(depth.pred..)
      end

      private

      def visit_Gem_SafeMarshal_Elements_Array(a)
        register_object([]).replace(a.elements.each_with_index.map do |e, i|
          @stack << "[#{i}]"
          visit(e)
        end)
      end

      def visit_Gem_SafeMarshal_Elements_Symbol(s)
        name = s.name
        raise UnpermittedSymbolError.new(symbol: name, stack: @stack.dup) unless @permitted_symbols.include?(name)
        visit_symbol_type(s)
      end

      def map_ivars(klass, ivars)
        ivars.map.with_index do |(k, v), i|
          @stack << "ivar_#{i}"
          k = resolve_ivar(klass, k)
          @stack[-1] = k
          next k, visit(v)
        end
      end

      def visit_Gem_SafeMarshal_Elements_WithIvars(e)
        object_offset = @objects.size
        @stack << "object"
        object = visit(e.object)
        ivars = map_ivars(object.class, e.ivars)

        case e.object
        when Elements::UserDefined
          if object.class == ::Time
            offset = zone = nano_num = nano_den = submicro = nil
            ivars.reject! do |k, v|
              case k
              when :offset
                offset = v
              when :zone
                zone = v
              when :nano_num
                nano_num = v
              when :nano_den
                nano_den = v
              when :submicro
                submicro = v
              else
                next false
              end
              true
            end

            if (nano_den || nano_num) && !(nano_den && nano_num)
              raise FormatError, "Must have all of nano_den, nano_num for Time #{e.pretty_inspect}"
            elsif nano_den && nano_num
              if RUBY_ENGINE == "jruby"
                nano = Rational(nano_num, nano_den * 1_000_000_000)
                object = Time.at(object.to_i + nano + object.subsec)
              elsif RUBY_ENGINE == "truffleruby"
                if RUBY_ENGINE_VERSION >= "23.0.0"
                  object = Time.at(object.to_i, Rational(nano_num, nano_den).to_i, :nanosecond)
                else
                  object = object.floor + Rational(nano_num, nano_den * 1_000_000_000)
                end
              else # assume "ruby"
                nano = Rational(nano_num, nano_den)
                nsec, subnano = nano.divmod(1)
                nano = nsec + subnano
                object = Time.at(object.to_r, nano, :nanosecond)
              end
            end

            if zone
              require "time"
              transformed_zone = zone
              transformed_zone = "+0000" if ["UTC", "Z"].include?(zone) && offset == 0
              call_method(Time, :force_zone!, object, transformed_zone, offset)
            elsif offset
              object = object.localtime offset
            end

            if RUBY_ENGINE == "truffleruby" && RUBY_ENGINE_VERSION < "23.0.0"
              ivars << [:@offset, offset]
              ivars << [:@zone, zone]
              ivars << [:@nano_num, nano_num] if nano_num
              ivars << [:@nano_den, nano_den] if nano_den
            end

            @objects[object_offset] = object
          end
        when Elements::String
          enc = nil

          ivars.reject! do |k, v|
            case k
            when :E
              case v
              when TrueClass
                enc = "UTF-8"
              when FalseClass
                enc = "US-ASCII"
              else
                raise FormatError, "Unexpected value for String :E #{v.inspect}"
              end
            when :encoding
              enc = v
            else
              next false
            end
            true
          end

          object.replace ::String.new(object, encoding: enc)
        end

        ivars.each do |k, v|
          object.instance_variable_set k, v
        end
        object
      end

      def visit_Gem_SafeMarshal_Elements_Hash(o)
        hash = register_object({})

        o.pairs.each_with_index do |(k, v), i|
          @stack << i
          k = visit(k)
          @stack << k
          hash[k] = visit(v)
        end

        hash
      end

      def visit_Gem_SafeMarshal_Elements_HashWithDefaultValue(o)
        hash = visit_Gem_SafeMarshal_Elements_Hash(o)
        @stack << :default
        hash.default = visit(o.default)
        hash
      end

      def visit_Gem_SafeMarshal_Elements_Object(o)
        register_object(resolve_class(o.name).allocate)
      end

      def visit_Gem_SafeMarshal_Elements_ObjectLink(o)
        @objects[o.offset]
      end

      def visit_Gem_SafeMarshal_Elements_SymbolLink(o)
        @symbols[o.offset]
      end

      def visit_Gem_SafeMarshal_Elements_UserDefined(o)
        register_object(call_method(resolve_class(o.name), :_load, o.binary_string))
      end

      def visit_Gem_SafeMarshal_Elements_UserMarshal(o)
        klass = resolve_class(o.name)
        compat = COMPAT_CLASSES.fetch(klass, nil)
        idx = @objects.size
        object = register_object(call_method(compat || klass, :allocate))

        @stack << :data
        ret = call_method(object, :marshal_load, visit(o.data))

        if compat
          object = @objects[idx] = ret
        end

        object
      end

      def visit_Gem_SafeMarshal_Elements_Integer(i)
        i.int
      end

      def visit_Gem_SafeMarshal_Elements_Nil(_)
        nil
      end

      def visit_Gem_SafeMarshal_Elements_True(_)
        true
      end

      def visit_Gem_SafeMarshal_Elements_False(_)
        false
      end

      def visit_Gem_SafeMarshal_Elements_String(s)
        register_object(s.str)
      end

      def visit_Gem_SafeMarshal_Elements_Float(f)
        case f.string
        when "inf"
          ::Float::INFINITY
        when "-inf"
          -::Float::INFINITY
        when "nan"
          ::Float::NAN
        else
          f.string.to_f
        end
      end

      def visit_Gem_SafeMarshal_Elements_Bignum(b)
        result = 0
        b.data.each_byte.with_index do |byte, exp|
          result += (byte * 2**(exp * 8))
        end

        case b.sign
        when 43 # ?+
          result
        when 45 # ?-
          -result
        else
          raise FormatError, "Unexpected sign for Bignum #{b.sign.chr.inspect} (#{b.sign})"
        end
      end

      def resolve_class(n)
        @class_cache[n] ||= begin
          to_s = resolve_symbol_name(n)
          raise UnpermittedClassError.new(name: to_s, stack: @stack.dup) unless @permitted_classes.include?(to_s)
          visit_symbol_type(n)
          begin
            ::Object.const_get(to_s)
          rescue NameError
            raise ArgumentError, "Undefined class #{to_s.inspect}"
          end
        end
      end

      class RationalCompat
        def marshal_load(s)
          num, den = s
          raise ArgumentError, "Expected 2 ints" unless s.size == 2 && num.is_a?(Integer) && den.is_a?(Integer)
          Rational(num, den)
        end
      end

      COMPAT_CLASSES = {}.tap do |h|
        h[Rational] = RationalCompat
      end.freeze
      private_constant :COMPAT_CLASSES

      def resolve_ivar(klass, name)
        to_s = resolve_symbol_name(name)

        raise UnpermittedIvarError.new(symbol: to_s, klass: klass, stack: @stack.dup) unless @permitted_ivars.fetch(klass.name, [].freeze).include?(to_s)

        visit_symbol_type(name)
      end

      def visit_symbol_type(element)
        case element
        when Elements::Symbol
          sym = element.name.to_sym
          @symbols << sym
          sym
        when Elements::SymbolLink
          visit_Gem_SafeMarshal_Elements_SymbolLink(element)
        end
      end

      def resolve_symbol_name(element)
        case element
        when Elements::Symbol
          element.name
        when Elements::SymbolLink
          visit_Gem_SafeMarshal_Elements_SymbolLink(element).to_s
        else
          raise FormatError, "Expected symbol or symbol link, got #{element.inspect} @ #{@stack.join(".")}"
        end
      end

      def register_object(o)
        @objects << o
        o
      end

      def call_method(receiver, method, *args)
        receiver.__send__(method, *args)
      rescue NoMethodError => e
        raise unless e.receiver == receiver

        raise MethodCallError, "Unable to call #{method.inspect} on #{receiver.inspect}, perhaps it is a class using marshal compat, which is not visible in ruby? #{e}"
      end

      class Error < StandardError
      end

      class UnpermittedSymbolError < Error
        def initialize(symbol:, stack:)
          @symbol = symbol
          @stack = stack
          super "Attempting to load unpermitted symbol #{symbol.inspect} @ #{stack.join "."}"
        end
      end

      class UnpermittedIvarError < Error
        def initialize(symbol:, klass:, stack:)
          @symbol = symbol
          @klass = klass
          @stack = stack
          super "Attempting to set unpermitted ivar #{symbol.inspect} on object of class #{klass} @ #{stack.join "."}"
        end
      end

      class UnpermittedClassError < Error
        def initialize(name:, stack:)
          @name = name
          @stack = stack
          super "Attempting to load unpermitted class #{name.inspect} @ #{stack.join "."}"
        end
      end

      class FormatError < Error
      end

      class MethodCallError < Error
      end
    end
  end
end
