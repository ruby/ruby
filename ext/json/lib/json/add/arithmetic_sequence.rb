# frozen_string_literal: true

require 'json' unless defined?(JSON::JSON_LOADED) && JSON::JSON_LOADED

class Enumerator
  class ArithmeticSequence
    # See #as_json.
    def self.json_create(object)
      Range.new(*object.values_at('b', 'e', 'x')) % object['s']
    end

    # Methods <tt>Enumerator::ArithmeticSequence#as_json</tt> and
    # +Enumerator::ArithmeticSequence.json_create+ can be used to serialize and
    # deserialize an \ArithmeticSequence object. See Marshal[rdoc-ref:Marshal].
    #
    # \Method <tt>Enumerator::ArithmeticSequence#as_json</tt> serializes +self+,
    # returning a 5-element hash representing +self+:
    #
    #   require 'json/add/arithmetic_sequence'
    #
    #   x = 42.step(by: 3, to: 72).as_json
    #   # => {"json_class"=>"Enumerator::ArithmeticSequence", "b"=>42, "e"=>72, "x"=>false, "s"=>3}
    #
    #   y = ((42...72) % 4).as_json
    #   # => {"json_class"=>"Enumerator::ArithmeticSequence", "b"=>42, "e"=>72, "x"=>true, "s"=>4}
    #
    # \Method +JSON.create+ deserializes such a hash, returning an
    # \ArithmeticSequence object:
    #
    #   Enumerator::ArithmeticSequence.json_create(x) # => ((42..72).%(3))
    #   Enumerator::ArithmeticSequence.json_create(y) # => ((42...72).%(4))
    #
    def as_json(*)
      {
        JSON.create_id => self.class.name,
        'b' => self.begin,
        'e' => self.end,
        'x' => exclude_end?,
        's' => step
      }
    end

    # Returns a JSON string representing +self+:
    #
    #   require 'json/add/arithmetic_sequence'
    #
    #   puts 42.step(by: 3, to: 72).to_json
    #   puts ((42...72) % 4).to_json
    #
    # Output:
    #
    #   {"json_class":"Enumerator::ArithmeticSequence","b":42,"e":72,"x":false,"s":3}
    #   {"json_class":"Enumerator::ArithmeticSequence","b":42,"e":72,"x":true,"s":4}
    #
    def to_json(*) = as_json.to_json(*)
  end
end
