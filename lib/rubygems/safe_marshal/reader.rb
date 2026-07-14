# frozen_string_literal: true

require_relative "elements"

module Gem
  module SafeMarshal
    class Reader
      class Error < StandardError
      end

      class UnsupportedVersionError < Error
      end

      class UnconsumedBytesError < Error
      end

      class NotImplementedError < Error
      end

      class EOFError < Error
      end

      class DataTooShortError < Error
      end

      class NegativeLengthError < Error
      end

      def initialize(io)
        @io = io
        @object_links = {}
        @symbol_links = {}
      end

      def read!
        read_header
        root = read_element
        raise UnconsumedBytesError, "expected EOF, got #{@io.read(10).inspect}... after top-level element #{root.class}" unless @io.eof?
        root
      end

      private

      MARSHAL_VERSION = [Marshal::MAJOR_VERSION, Marshal::MINOR_VERSION].map(&:chr).join.freeze
      private_constant :MARSHAL_VERSION

      def read_header
        v = @io.read(2)
        raise UnsupportedVersionError, "Unsupported marshal version #{v.bytes.map(&:ord).join(".")}, expected #{Marshal::MAJOR_VERSION}.#{Marshal::MINOR_VERSION}" unless v == MARSHAL_VERSION
      end

      def read_bytes(n)
        raise NegativeLengthError if n < 0
        str = @io.read(n)
        raise EOFError, "expected #{n} bytes, got EOF" if str.nil?
        raise DataTooShortError, "expected #{n} bytes, got #{str.inspect}" unless str.bytesize == n
        str
      end

      def read_byte
        @io.getbyte || raise(EOFError, "Unexpected EOF")
      end

      def read_integer
        b = read_byte

        case b
        when 0x00
          0
        when 0x01
          read_byte
        when 0x02
          read_byte | (read_byte << 8)
        when 0x03
          read_byte | (read_byte << 8) | (read_byte << 16)
        when 0x04
          read_byte | (read_byte << 8) | (read_byte << 16) | (read_byte << 24)
        when 0xFC
          read_byte | (read_byte << 8) | (read_byte << 16) | (read_byte << 24) | -0x100000000
        when 0xFD
          read_byte | (read_byte << 8) | (read_byte << 16) | -0x1000000
        when 0xFE
          read_byte | (read_byte << 8) | -0x10000
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
        when 105 then Elements::Integer.new(read_integer) # ?i
        when 108 then read_bignum # ?l
        when 111 then read_object # ?o
        when 117 then read_user_defined # ?u
        when 123 then read_hash # ?{
        when 125 then read_hash_with_default_value # ?}
        when 101 then read_extended_object # ?e
        when 99 then read_class # ?c
        when 109 then read_module # ?m
        when 77 then read_class_or_module # ?M
        when 100 then read_data # ?d
        when 47 then read_regexp # ?/
        when 83 then read_struct # ?S
        when 67 then read_user_class # ?C
        else
          raise Error, "Unknown marshal type discriminator #{type.chr.inspect} (#{type})"
        end
      end

      STRING_E_SYMBOL = Elements::Symbol.new("E").freeze
      private_constant :STRING_E_SYMBOL

      def read_symbol
        len = read_integer
        if len == 1
          byte = read_byte
          if byte == 69 # ?E
            STRING_E_SYMBOL
          else
            Elements::Symbol.new(byte.chr)
          end
        else
          name = read_bytes(len)
          Elements::Symbol.new(name)
        end
      end

      EMPTY_STRING = Elements::String.new("".b.freeze).freeze
      private_constant :EMPTY_STRING

      def read_string
        length = read_integer
        return EMPTY_STRING if length == 0
        str = read_bytes(length)
        Elements::String.new(str)
      end

      def read_true
        Elements::True::TRUE
      end

      def read_false
        Elements::False::FALSE
      end

      def read_user_defined
        name = read_element
        binary_string = read_bytes(read_integer)
        Elements::UserDefined.new(name, binary_string)
      end

      EMPTY_ARRAY = Elements::Array.new([].freeze).freeze
      private_constant :EMPTY_ARRAY

      def read_array
        length = read_integer
        return EMPTY_ARRAY if length == 0
        raise NegativeLengthError if length < 0
        elements = Array.new(length) do
          read_element
        end
        Elements::Array.new(elements)
      end

      def read_object_with_ivars
        object = read_element
        length = read_integer
        raise NegativeLengthError if length < 0
        ivars = Array.new(length) do
          [read_element, read_element]
        end
        Elements::WithIvars.new(object, ivars)
      end

      def read_symbol_link
        offset = read_integer
        @symbol_links[offset] ||= Elements::SymbolLink.new(offset)
      end

      def read_user_marshal
        name = read_element
        data = read_element
        Elements::UserMarshal.new(name, data)
      end

      def read_object_link
        offset = read_integer
        @object_links[offset] ||= Elements::ObjectLink.new(offset)
      end

      EMPTY_HASH = Elements::Hash.new([].freeze).freeze
      private_constant :EMPTY_HASH

      def read_hash
        length = read_integer
        return EMPTY_HASH if length == 0
        pairs = Array.new(length) do
          [read_element, read_element]
        end
        Elements::Hash.new(pairs)
      end

      def read_hash_with_default_value
        length = read_integer
        raise NegativeLengthError if length < 0
        pairs = Array.new(length) do
          [read_element, read_element]
        end
        default = read_element
        Elements::HashWithDefaultValue.new(pairs, default)
      end

      def read_object
        name = read_element
        object = Elements::Object.new(name)
        length = read_integer
        raise NegativeLengthError if length < 0
        ivars = Array.new(length) do
          [read_element, read_element]
        end
        Elements::WithIvars.new(object, ivars)
      end

      def read_nil
        Elements::Nil::NIL
      end

      def read_float
        string = read_bytes(read_integer)
        Elements::Float.new(string)
      end

      def read_bignum
        sign = read_byte
        data = read_bytes(read_integer * 2)
        Elements::Bignum.new(sign, data)
      end

      def read_extended_object
        raise NotImplementedError, "Reading Marshal objects of type extended_object is not implemented"
      end

      def read_class
        raise NotImplementedError, "Reading Marshal objects of type class is not implemented"
      end

      def read_module
        raise NotImplementedError, "Reading Marshal objects of type module is not implemented"
      end

      def read_class_or_module
        raise NotImplementedError, "Reading Marshal objects of type class_or_module is not implemented"
      end

      def read_data
        raise NotImplementedError, "Reading Marshal objects of type data is not implemented"
      end

      def read_regexp
        raise NotImplementedError, "Reading Marshal objects of type regexp is not implemented"
      end

      def read_struct
        raise NotImplementedError, "Reading Marshal objects of type struct is not implemented"
      end

      def read_user_class
        name = read_element
        wrapped_object = read_element
        Elements::UserClass.new(name, wrapped_object)
      end
    end
  end
end
