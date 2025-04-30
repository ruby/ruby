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


# TODO: how best to check for builtin Set?
if defined?(::Set) && Object.const_source_location(:Set) == ["ruby", 0]
  class Set
    def encode_with(coder)
      coder["hash"] = to_h
    end

    def init_with(coder)
      replace(coder["hash"].keys)
    end
  end
end
