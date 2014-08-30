require 'oj'
require 'multi_json/adapter'

module MultiJson
  module Adapters
    # Use the Oj library to dump/load.
    class Oj < Adapter
      defaults :load, :mode => :strict, :symbolize_keys => false
      defaults :dump, :mode => :compat, :time_format => :ruby, :use_to_json => true

      ParseError = defined?(::Oj::ParseError) ? ::Oj::ParseError : SyntaxError

      def load(string, options={})
        options[:symbol_keys] = options.delete(:symbolize_keys)
        ::Oj.load(string, options)
      end

      def dump(object, options={})
        options.merge!(:indent => 2) if options[:pretty]
        options[:indent] = options[:indent].to_i if options[:indent]
        ::Oj.dump(object, options)
      end
    end
  end
end
