require 'rexml/encodings/US-ASCII'

module REXML
  module Encoding
    register("ISO-8859-1", &encoding_method("US-ASCII"))
  end
end
