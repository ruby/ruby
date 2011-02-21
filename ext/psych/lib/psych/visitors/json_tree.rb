require 'psych/json/ruby_events'

module Psych
  module Visitors
    class JSONTree < YAMLTree
      include Psych::JSON::RubyEvents

      def initialize options = {}, emitter = Psych::JSON::TreeBuilder.new
        super
      end
    end
  end
end
