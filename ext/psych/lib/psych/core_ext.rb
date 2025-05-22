# frozen_string_literal: true
class Object
  def self.yaml_tag url
    Psych.add_tag(url, self)
  end

  ###
  # call-seq: to_yaml(options = {})
  #
  # Convert an object to YAML.  See Psych.dump for more information on the
  # available +options+.
  def to_yaml options = {}
    Psych.dump self, options
  end
end

if defined?(::IRB)
  require_relative 'y'
end

# Up to Ruby 3.4, Set was a regular object and was dumped as such
# by Pysch.
# Starting from Ruby 3.5 it's a core class written in C, so we have to implement
# #encode_with / #init_with to preserve backward compatibility.
if defined?(::Set) && Set.new.instance_variables.empty?
  class Set
    def encode_with(coder)
      hash = {}
      each do |m|
        hash[m] = true
      end
      coder["hash"] = hash
      coder
    end

    def init_with(coder)
      replace(coder["hash"].keys)
    end
  end
end
