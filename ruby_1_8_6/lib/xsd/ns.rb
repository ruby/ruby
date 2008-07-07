# XSD4R - XML Schema Namespace library
# Copyright (C) 2000-2003, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/datatypes'


module XSD


class NS
  class Assigner
    def initialize
      @count = 0
    end

    def assign(ns)
      @count += 1
      "n#{@count}"
    end
  end

  attr_reader :default_namespace

  class FormatError < Error; end

public

  def initialize(tag2ns = {})
    @tag2ns = tag2ns
    @assigner = nil
    @ns2tag = {}
    @tag2ns.each do |tag, ns|
      @ns2tag[ns] = tag
    end
    @default_namespace = nil
  end

  def assign(ns, tag = nil)
    if (tag == '')
      @default_namespace = ns
      tag
    else
      @assigner ||= Assigner.new
      tag ||= @assigner.assign(ns)
      @ns2tag[ns] = tag
      @tag2ns[tag] = ns
      tag
    end
  end

  def assigned?(ns)
    @default_namespace == ns or @ns2tag.key?(ns)
  end

  def assigned_tag?(tag)
    @tag2ns.key?(tag)
  end

  def clone_ns
    cloned = NS.new(@tag2ns.dup)
    cloned.assigner = @assigner
    cloned.assign(@default_namespace, '') if @default_namespace
    cloned
  end

  def name(name)
    if (name.namespace == @default_namespace)
      name.name
    elsif @ns2tag.key?(name.namespace)
      "#{@ns2tag[name.namespace]}:#{name.name}"
    else
      raise FormatError.new("namespace: #{name.namespace} not defined yet")
    end
  end

  def compare(ns, name, rhs)
    if (ns == @default_namespace)
      return true if (name == rhs)
    end
    @tag2ns.each do |assigned_tag, assigned_ns|
      if assigned_ns == ns && "#{assigned_tag}:#{name}" == rhs
	return true
      end
    end
    false
  end

  # $1 and $2 are necessary.
  ParseRegexp = Regexp.new('^([^:]+)(?::(.+))?$')

  def parse(str, local = false)
    if ParseRegexp =~ str
      if (name = $2) and (ns = @tag2ns[$1])
        return XSD::QName.new(ns, name)
      end
    end
    XSD::QName.new(local ? nil : @default_namespace, str)
  end

  # For local attribute key parsing
  #   <foo xmlns="urn:a" xmlns:n1="urn:a" bar="1" n1:baz="2" />
  #     =>
  #   {}bar, {urn:a}baz
  def parse_local(elem)
    ParseRegexp =~ elem
    if $2
      ns = @tag2ns[$1]
      name = $2
      if !ns
	raise FormatError.new("unknown namespace qualifier: #{$1}")
      end
    elsif $1
      ns = nil
      name = $1
    else
      raise FormatError.new("illegal element format: #{elem}")
    end
    XSD::QName.new(ns, name)
  end

  def each_ns
    @ns2tag.each do |ns, tag|
      yield(ns, tag)
    end
  end

protected

  def assigner=(assigner)
    @assigner = assigner
  end
end


end
