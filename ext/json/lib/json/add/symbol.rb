# frozen_string_literal: true
unless defined?(::JSON::JSON_LOADED) and ::JSON::JSON_LOADED
  require 'json'
end

class Symbol

  # Methods <tt>Symbol#as_json</tt> and +Symbol.json_create+ may be used
  # to serialize and deserialize a \Symbol object;
  # see Marshal[rdoc-ref:Marshal].
  #
  # \Method <tt>Symbol#as_json</tt> serializes +self+,
  # returning a 2-element hash representing +self+:
  #
  #   require 'json/add/symbol'
  #   x = :foo.as_json
  #   # => {"json_class"=>"Symbol", "s"=>"foo"}
  #
  # \Method +JSON.create+ deserializes such a hash, returning a \Symbol object:
  #
  #   Symbol.json_create(x) # => :foo
  #
  def as_json(*)
    {
      JSON.create_id => self.class.name,
      's'            => to_s,
    }
  end

  # Returns a JSON string representing +self+:
  #
  #   require 'json/add/symbol'
  #   puts :foo.to_json
  #
  # Output:
  #
  #   # {"json_class":"Symbol","s":"foo"}
  #
  def to_json(state = nil, *a)
    state = ::JSON::State.from_state(state)
    if state.strict?
      super
    else
      as_json.to_json(state, *a)
    end
  end

  # See #as_json.
  def self.json_create(o)
    o['s'].to_sym
  end
end
