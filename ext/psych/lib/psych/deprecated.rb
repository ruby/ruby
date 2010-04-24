require 'date'

module Psych
  DEPRECATED = __FILE__ # :nodoc:

  module DeprecatedMethods # :nodoc:
    attr_accessor :taguri
    attr_accessor :to_yaml_style
  end

  def self.quick_emit thing, opts = {}, &block # :nodoc:
    warn "#{caller[0]}: YAML.quick_emit is deprecated" if $VERBOSE && !caller[0].start_with?(File.dirname(__FILE__))
    target = eval 'self', block.binding
    target.extend DeprecatedMethods
    metaclass = class << target; self; end
    metaclass.send(:define_method, :encode_with) do |coder|
      target.taguri        = coder.tag
      target.to_yaml_style = coder.style
      block.call coder
    end
    target.psych_to_yaml unless opts[:nodump]
  end

  def self.load_documents yaml, &block
    if $VERBOSE
      warn "#{caller[0]}: load_documents is deprecated, use load_stream"
    end
    list = load_stream yaml
    return list unless block_given?
    list.each(&block)
  end

  def self.detect_implicit thing
    warn "#{caller[0]}: detect_implicit is deprecated" if $VERBOSE
    return '' unless String === thing
    return 'null' if '' == thing
    ScalarScanner.new.tokenize(thing).class.name.downcase
  end
end

class Object
  def to_yaml_properties # :nodoc:
    instance_variables
  end
end
