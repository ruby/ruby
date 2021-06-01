class MatchYAMLMatcher

  def initialize(expected)
    if valid_yaml?(expected)
      @expected = expected
    else
      @expected = expected.to_yaml
    end
  end

  def matches?(actual)
    @actual = actual
    clean_yaml(@actual) == clean_yaml(@expected)
  end

  def failure_message
    ["Expected #{@actual.inspect}", " to match #{@expected.inspect}"]
  end

  def negative_failure_message
    ["Expected #{@actual.inspect}", " to match #{@expected.inspect}"]
  end

  protected

  def clean_yaml(yaml)
    yaml.gsub(/([^-]|^---)\s+\n/, "\\1\n").sub(/\n\.\.\.\n$/, "\n")
  end

  def valid_yaml?(obj)
    require 'yaml'
    begin
      if YAML.respond_to?(:unsafe_load)
        YAML.unsafe_load(obj)
      else
        YAML.load(obj)
      end
    rescue
      false
    else
      true
    end
  end
end

module MSpecMatchers
  private def match_yaml(expected)
    MatchYAMLMatcher.new(expected)
  end
end
