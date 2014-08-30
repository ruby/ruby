require 'multi_json'

module SimpleCov::JSON
  class << self
    def parse(json)
      # Detect and use available MultiJson API - it changed in v1.3
      if MultiJson.respond_to?(:adapter)
        MultiJson.load(json)
      else
        MultiJson.decode(json)
      end
    end

    def dump(string)
      if defined? ::JSON
        ::JSON.pretty_generate(string)
      else
        # Detect and use available MultiJson API - it changed in v1.3
        if MultiJson.respond_to?(:adapter)
          MultiJson.dump(string)
        else
          MultiJson.encode(string)
        end
      end
    end
  end
end
