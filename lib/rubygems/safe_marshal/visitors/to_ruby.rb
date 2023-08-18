# frozen_string_literal: true

require_relative "visitor"

module Gem::SafeMarshal
  module Visitors
    class ToRuby < Visitor
      def initialize(permitted_classes:, permitted_symbols:)
        @permitted_classes = permitted_classes
        @permitted_symbols = permitted_symbols | permitted_classes | ["E"]

        @objects = []
        @symbols = []
        @class_cache = {}

        @stack = ["root"]
      end

      def inspect # :nodoc:
        format("#<%s permitted_classes: %p permitted_symbols: %p>", self.class, @permitted_classes, @permitted_symbols)
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
        resolve_symbol(s.name)
      end

      def map_ivars(ivars)
        ivars.map.with_index do |(k, v), i|
          @stack << "ivar #{i}"
          k = visit(k)
          @stack << k
          next k, visit(v)
        end
      end

      def visit_Gem_SafeMarshal_Elements_WithIvars(e)
        idx = 0
        object_offset = @objects.size
        @stack << "object"
        object = visit(e.object)
        ivars = map_ivars(e.ivars)

        case e.object
        when Elements::UserDefined
          if object.class == ::Time
            offset = zone = nano_num = nano_den = nil
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
              else
                next false
              end
              true
            end

            if (nano_den || nano_num) && !(nano_den && nano_num)
              raise FormatError, "Must have all of nano_den, nano_num for Time #{e.pretty_inspect}"
            elsif nano_den && nano_num
              nano = Rational(nano_num, nano_den)
              nsec, subnano = nano.divmod(1)
              nano  = nsec + subnano

              object = Time.at(object.to_r, nano, :nanosecond)
            end

            if zone
              require "time"
              zone = "+0000" if zone == "UTC" && offset == 0
              Time.send(:force_zone!, object, zone, offset)
            elsif offset
              object = object.localtime offset
            end

            @objects[object_offset] = object
          end
        when Elements::String
          enc = nil

          ivars.each do |k, v|
            case k
            when :E
              case v
              when TrueClass
                enc = "UTF-8"
              when FalseClass
                enc = "US-ASCII"
              end
            else
              break
            end
            idx += 1
          end

          object.replace ::String.new(object, encoding: enc)
        end

        ivars[idx..].each do |k, v|
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
        register_object(resolve_class(o.name).send(:_load, o.binary_string))
      end

      def visit_Gem_SafeMarshal_Elements_UserMarshal(o)
        register_object(resolve_class(o.name).allocate).tap do |object|
          @stack << :data
          object.marshal_load visit(o.data)
        end
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
          name = nil
          case n
          when Elements::Symbol, Elements::SymbolLink
            @stack << "class name"
            name = visit(n)
          else
            raise FormatError, "Class names must be Symbol or SymbolLink"
          end
          to_s = name.to_s
          raise UnpermittedClassError.new(name: name, stack: @stack.dup) unless @permitted_classes.include?(to_s)
          begin
            ::Object.const_get(to_s)
          rescue NameError
            raise ArgumentError, "Undefined class #{to_s.inspect}"
          end
        end
      end

      def resolve_symbol(name)
        raise UnpermittedSymbolError.new(symbol: name, stack: @stack.dup) unless @permitted_symbols.include?(name)
        sym = name.to_sym
        @symbols << sym
        sym
      end

      def register_object(o)
        @objects << o
        o
      end

      class UnpermittedSymbolError < StandardError
        def initialize(symbol:, stack:)
          @symbol = symbol
          @stack = stack
          super "Attempting to load unpermitted symbol #{symbol.inspect} @ #{stack.join "."}"
        end
      end

      class UnpermittedClassError < StandardError
        def initialize(name:, stack:)
          @name = name
          @stack = stack
          super "Attempting to load unpermitted class #{name.inspect} @ #{stack.join "."}"
        end
      end

      class FormatError < StandardError
      end
    end
  end
end
