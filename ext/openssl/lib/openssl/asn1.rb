# frozen_string_literal: true
#--
#
# = Ruby-space definitions that completes C-space funcs for ASN.1
#
# = Licence
# This program is licensed under the same licence as Ruby.
# (See the file 'COPYING'.)
#++

module OpenSSL
  module ASN1
    class ASN1Data
      #
      # Carries the value of a ASN.1 type.
      # Please confer Constructive and Primitive for the mappings between
      # ASN.1 data types and Ruby classes.
      #
      attr_accessor :value

      # An Integer representing the tag number of this ASN1Data. Never +nil+.
      attr_accessor :tag

      # A Symbol representing the tag class of this ASN1Data. Never +nil+.
      # See ASN1Data for possible values.
      attr_accessor :tag_class

      #
      # Never +nil+. A boolean value indicating whether the encoding uses
      # indefinite length (in the case of parsing) or whether an indefinite
      # length form shall be used (in the encoding case).
      # In DER, every value uses definite length form. But in scenarios where
      # large amounts of data need to be transferred it might be desirable to
      # have some kind of streaming support available.
      # For example, huge OCTET STRINGs are preferably sent in smaller-sized
      # chunks, each at a time.
      # This is possible in BER by setting the length bytes of an encoding
      # to zero and by this indicating that the following value will be
      # sent in chunks. Indefinite length encodings are always constructed.
      # The end of such a stream of chunks is indicated by sending a EOC
      # (End of Content) tag. SETs and SEQUENCEs may use an indefinite length
      # encoding, but also primitive types such as e.g. OCTET STRINGS or
      # BIT STRINGS may leverage this functionality (cf. ITU-T X.690).
      #
      attr_accessor :indefinite_length

      alias infinite_length indefinite_length
      alias infinite_length= indefinite_length=

      #
      # :call-seq:
      #    OpenSSL::ASN1::ASN1Data.new(value, tag, tag_class) => ASN1Data
      #
      # _value_: Please have a look at Constructive and Primitive to see how Ruby
      # types are mapped to ASN.1 types and vice versa.
      #
      # _tag_: An Integer indicating the tag number.
      #
      # _tag_class_: A Symbol indicating the tag class. Please cf. ASN1 for
      # possible values.
      #
      # == Example
      #   asn1_int = OpenSSL::ASN1Data.new(42, 2, :UNIVERSAL) # => Same as OpenSSL::ASN1::Integer.new(42)
      #   tagged_int = OpenSSL::ASN1Data.new(42, 0, :CONTEXT_SPECIFIC) # implicitly 0-tagged INTEGER
      #
      def initialize(value, tag, tag_class)
        raise ASN1Error, "invalid tag class" unless tag_class.is_a?(Symbol)

        @tag = tag
        @value = value
        @tag_class = tag_class
        @indefinite_length = false
      end
    end

    module TaggedASN1Data
      #
      # May be used as a hint for encoding a value either implicitly or
      # explicitly by setting it either to +:IMPLICIT+ or to +:EXPLICIT+.
      # _tagging_ is not set when a ASN.1 structure is parsed using
      # OpenSSL::ASN1.decode.
      #
      attr_accessor :tagging

      # :call-seq:
      #    OpenSSL::ASN1::Primitive.new(value [, tag, tagging, tag_class ]) => Primitive
      #
      # _value_: is mandatory.
      #
      # _tag_: optional, may be specified for tagged values. If no _tag_ is
      # specified, the UNIVERSAL tag corresponding to the Primitive sub-class
      # is used by default.
      #
      # _tagging_: may be used as an encoding hint to encode a value either
      # explicitly or implicitly, see ASN1 for possible values.
      #
      # _tag_class_: if _tag_ and _tagging_ are +nil+ then this is set to
      # +:UNIVERSAL+ by default. If either _tag_ or _tagging_ are set then
      # +:CONTEXT_SPECIFIC+ is used as the default. For possible values please
      # cf. ASN1.
      #
      # == Example
      #   int = OpenSSL::ASN1::Integer.new(42)
      #   zero_tagged_int = OpenSSL::ASN1::Integer.new(42, 0, :IMPLICIT)
      #   private_explicit_zero_tagged_int = OpenSSL::ASN1::Integer.new(42, 0, :EXPLICIT, :PRIVATE)
      #
      def initialize(value, tag = nil, tagging = nil, tag_class = nil)
        tag ||= ASN1.take_default_tag(self.class)

        raise ASN1Error, "must specify tag number" unless tag

        if tagging
          raise ASN1Error, "invalid tagging method" unless tagging.is_a?(Symbol)
        end

        tag_class ||= tagging ? :CONTEXT_SPECIFIC : :UNIVERSAL

        raise ASN1Error, "invalid tag class" unless tag_class.is_a?(Symbol)

        @tagging = tagging
        super(value ,tag, tag_class)
      end
    end

    class Primitive < ASN1Data
      include TaggedASN1Data

      undef_method :indefinite_length=
      undef_method :infinite_length=
    end

    class Constructive < ASN1Data
      include TaggedASN1Data
      include Enumerable

      # :call-seq:
      #    asn1_ary.each { |asn1| block } => asn1_ary
      #
      # Calls the given block once for each element in self, passing that element
      # as parameter _asn1_. If no block is given, an enumerator is returned
      # instead.
      #
      # == Example
      #   asn1_ary.each do |asn1|
      #     puts asn1
      #   end
      #
      def each(&blk)
        @value.each(&blk)

        self
      end
    end

    class Boolean < Primitive ; end
    class Integer < Primitive ; end
    class Enumerated < Primitive ; end

    class BitString < Primitive
      attr_accessor :unused_bits

      def initialize(*)
        super

        @unused_bits = 0
      end
    end

    class EndOfContent < ASN1Data
      def initialize
        super("", 0, :UNIVERSAL)
      end
    end

    # :nodoc:
    def self.take_default_tag(klass)
      tag = CLASS_TAG_MAP[klass]

      return tag if tag

      sklass = klass.superclass

      return unless sklass

      take_default_tag(sklass)
    end
  end
end
