# frozen_string_literal: true

module Net
  class IMAP < Protocol


    class RawData # :nodoc:
      def send_data(imap, tag)
        imap.__send__(:put_string, @data)
      end

      def validate
      end

      private

      def initialize(data)
        @data = data
      end
    end

    class Atom # :nodoc:
      def send_data(imap, tag)
        imap.__send__(:put_string, @data)
      end

      def validate
      end

      private

      def initialize(data)
        @data = data
      end
    end

    class QuotedString # :nodoc:
      def send_data(imap, tag)
        imap.__send__(:send_quoted_string, @data)
      end

      def validate
      end

      private

      def initialize(data)
        @data = data
      end
    end

    class Literal # :nodoc:
      def send_data(imap, tag)
        imap.__send__(:send_literal, @data, tag)
      end

      def validate
      end

      private

      def initialize(data)
        @data = data
      end
    end

    class MessageSet # :nodoc:
      def send_data(imap, tag)
        imap.__send__(:put_string, format_internal(@data))
      end

      def validate
        validate_internal(@data)
      end

      private

      def initialize(data)
        @data = data
      end

      def format_internal(data)
        case data
        when "*"
          return data
        when Integer
          if data == -1
            return "*"
          else
            return data.to_s
          end
        when Range
          return format_internal(data.first) +
            ":" + format_internal(data.last)
        when Array
          return data.collect {|i| format_internal(i)}.join(",")
        when ThreadMember
          return data.seqno.to_s +
            ":" + data.children.collect {|i| format_internal(i).join(",")}
        end
      end

      def validate_internal(data)
        case data
        when "*"
        when Integer
          NumValidator.ensure_nz_number(data)
        when Range
        when Array
          data.each do |i|
            validate_internal(i)
          end
        when ThreadMember
          data.children.each do |i|
            validate_internal(i)
          end
        else
          raise DataFormatError, data.inspect
        end
      end
    end

    class ClientID # :nodoc:

      def send_data(imap, tag)
        imap.__send__(:send_data, format_internal(@data), tag)
      end

      def validate
        validate_internal(@data)
      end

      private

      def initialize(data)
        @data = data
      end

      def validate_internal(client_id)
        client_id.to_h.each do |k,v|
          unless StringFormatter.valid_string?(k)
            raise DataFormatError, client_id.inspect
          end
        end
      rescue NoMethodError, TypeError # to_h failed
        raise DataFormatError, client_id.inspect
      end

      def format_internal(client_id)
        return nil if client_id.nil?
        client_id.to_h.flat_map {|k,v|
          [StringFormatter.string(k), StringFormatter.nstring(v)]
        }
      end

    end

    module StringFormatter

      LITERAL_REGEX = /[\x80-\xff\r\n]/n

      module_function

      # Allows symbols in addition to strings
      def valid_string?(str)
        str.is_a?(Symbol) || str.respond_to?(:to_str)
      end

      # Allows nil, symbols, and strings
      def valid_nstring?(str)
        str.nil? || valid_string?(str)
      end

      # coerces using +to_s+
      def string(str)
        str = str.to_s
        if str =~ LITERAL_REGEX
          Literal.new(str)
        else
          QuotedString.new(str)
        end
      end

      # coerces non-nil using +to_s+
      def nstring(str)
        str.nil? ? nil : string(str)
      end

    end

  end
end
