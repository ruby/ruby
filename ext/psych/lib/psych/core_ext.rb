class Object
  def self.yaml_tag url
    Psych.add_tag(url, self)
  end

  # FIXME: rename this to "to_yaml" when syck is removed

  ###
  # call-seq: to_yaml
  #
  # Convert an object to YAML
  def psych_to_yaml options = {}
    Psych.dump self, options
  end
  remove_method :to_yaml rescue nil
  alias :to_yaml :psych_to_yaml
end

module Kernel
  def psych_y *objects
    puts Psych.dump_stream(*objects)
  end
  remove_method :y rescue nil
  alias y psych_y
end
