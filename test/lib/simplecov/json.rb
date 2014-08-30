require 'json'

module SimpleCov::JSON
  class << self
    def parse(json)
      ::JSON.parse(json)
    end

    def dump(string)
      ::JSON.pretty_generate(string)
    end
  end
end
