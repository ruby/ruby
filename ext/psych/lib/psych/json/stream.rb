require 'psych/json/ruby_events'
require 'psych/json/yaml_events'

module Psych
  module JSON
    class Stream < Psych::Stream
      include Psych::JSON::RubyEvents

      class Emitter < Psych::Stream::Emitter # :nodoc:
        include Psych::JSON::YAMLEvents
      end
    end
  end
end
