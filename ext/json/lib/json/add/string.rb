# frozen_string_literal: true
unless defined?(::JSON::JSON_LOADED) and ::JSON::JSON_LOADED
  require 'json'
end

class String
  # call-seq: json_create(o)
  #
  # Raw Strings are JSON Objects (the raw bytes are stored in an array for the
  # key "raw"). The Ruby String can be created by this class method.
  def self.json_create(object)
    object["raw"].pack("C*")
  end

  # call-seq: to_json_raw_object()
  #
  # This method creates a raw object hash, that can be nested into
  # other data structures and will be generated as a raw string. This
  # method should be used, if you want to convert raw strings to JSON
  # instead of UTF-8 strings, e. g. binary data.
  def to_json_raw_object
    {
      JSON.create_id => self.class.name,
      "raw" => unpack("C*"),
    }
  end

  # call-seq: to_json_raw(*args)
  #
  # This method creates a JSON text from the result of a call to
  # to_json_raw_object of this String.
  def to_json_raw(...)
    to_json_raw_object.to_json(...)
  end
end
