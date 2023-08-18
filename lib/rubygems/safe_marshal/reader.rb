# frozen_string_literal: true

require_relative "elements"

module Gem
  module SafeMarshal
    class Reader
      class UnconsumedBytesError < StandardError
      end

      def initialize(io)
        @io = io
      end

      def read!
        read_header
        root = read_element
        raise UnconsumedBytesError unless @io.eof?
        root
      end

      private

      MARSHAL_VERSION = [Marshal::MAJOR_VERSION, Marshal::MINOR_VERSION].map(&:chr).join.freeze
      private_constant :MARSHAL_VERSION

      def read_header
        v = @io.read(2)
        raise "Unsupported marshal version #{v.inspect}, expected #{MARSHAL_VERSION.inspect}" unless v == MARSHAL_VERSION
      end

      def read_byte
        @io.getbyte
      end

      def read_integer
        b = read_byte

        case b
        when 0x00
          0
        when 0x01
          @io.read(1).unpack1("C")
        when 0x02
          @io.read(2).unpack1("S<")
        when 0x03
          (@io.read(3) + "\0").unpack1("L<")
        when 0x04
          @io.read(4).unpack1("L<")
        when 0xFC
          @io.read(4).unpack1("L<") | -0x100000000
        when 0xFD
          (@io.read(3) + "\0").unpack1("L<") | -0x1000000
        when 0xFE
          @io.read(2).unpack1("s<") | -0x10000
        when 0xFF
          read_byte | -0x100
        else
          signed = (b ^ 128) - 128
          if b >= 128
            signed + 5
          else
            signed - 5
          end
        end
      end

      def read_element
        type = read_byte
        case type
        when 34 then read_string # ?"
        when 48 then read_nil # ?0
        when 58 then read_symbol # ?:
        when 59 then read_symbol_link # ?;
        when 64 then read_object_link # ?@
        when 70 then read_false # ?F
        when 73 then read_object_with_ivars # ?I
        when 84 then read_true # ?T
        when 85 then read_user_marshal # ?U
        when 91 then read_array # ?[
        when 102 then read_float # ?f
        when 105 then Elements::Integer.new int: read_integer # ?i
        when 108 then read_bignum
        when 111 then read_object # ?o
        when 117 then read_user_defined # ?u
        when 123 then read_hash # ?{
        when 125 then read_hash_with_default_value # ?}
        when "e".ord then read_extended_object
        when "c".ord then read_class
        when "m".ord then read_module
        when "M".ord then read_class_or_module
        when "d".ord then read_data
        when "/".ord then read_regexp
        when "S".ord then read_struct
        when "C".ord then read_user_class
        else
          raise "Unsupported marshal type discriminator #{type.chr.inspect} (#{type})"
        end
      end

      def read_symbol
        Elements::Symbol.new name: @io.read(read_integer)
      end

      def read_string
        Elements::String.new(str: @io.read(read_integer))
      end

      def read_true
        Elements::True::TRUE
      end

      def read_false
        Elements::False::FALSE
      end

      def read_user_defined
        Elements::UserDefined.new(name: read_element, binary_string: @io.read(read_integer))
      end

      def read_array
        Elements::Array.new(elements: Array.new(read_integer) do |_i|
                                        read_element
                                      end)
      end

      def read_object_with_ivars
        Elements::WithIvars.new(object: read_element, ivars:
          Array.new(read_integer) do
            [read_element, read_element]
          end)
      end

      def read_symbol_link
        Elements::SymbolLink.new offset: read_integer
      end

      def read_user_marshal
        Elements::UserMarshal.new(name: read_element, data: read_element)
      end

      def read_object_link
        Elements::ObjectLink.new(offset: read_integer)
      end

      def read_hash
        pairs = Array.new(read_integer) do
          [read_element, read_element]
        end
        Elements::Hash.new(pairs: pairs)
      end

      def read_hash_with_default_value
        pairs = Array.new(read_integer) do
          [read_element, read_element]
        end
        Elements::HashWithDefaultValue.new(pairs: pairs, default: read_element)
      end

      def read_object
        Elements::WithIvars.new(
          object: Elements::Object.new(name: read_element),
          ivars: Array.new(read_integer) do
            [read_element, read_element]
          end
        )
      end

      def read_nil
        Elements::Nil::NIL
      end

      def read_float
        Elements::Float.new string: @io.read(read_integer)
      end

      def read_bignum
        Elements::Bignum.new(sign: read_byte, data: @io.read(read_integer * 2))
      end
    end
  end
end
