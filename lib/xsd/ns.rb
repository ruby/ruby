=begin
XSD4R - XML Schema Namespace library
Copyright (C) 2000, 2001, 2002, 2003  NAKAMURA, Hiroshi.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PRATICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 675 Mass
Ave, Cambridge, MA 02139, USA.
=end


require 'xsd/datatypes'


module XSD


class NS
  class Assigner
    def initialize
      @count = 0
    end

    def assign(ns)
      @count += 1
      "n#{ @count }"
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
    @ns2tag.key?(ns)
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
      @ns2tag[name.namespace] + ':' << name.name
    else
      raise FormatError.new('Namespace: ' << name.namespace << ' not defined yet.')
    end
  end

  def compare(ns, name, rhs)
    if (ns == @default_namespace)
      return true if (name == rhs)
    end
    @tag2ns.each do |assigned_tag, assigned_ns|
      if assigned_ns == ns && "#{ assigned_tag }:#{ name }" == rhs
	return true
      end
    end
    false
  end

  # $1 and $2 are necessary.
  ParseRegexp = Regexp.new('^([^:]+)(?::(.+))?$')

  def parse(elem)
    ns = nil
    name = nil
    ParseRegexp =~ elem
    if $2
      ns = @tag2ns[$1]
      name = $2
      if !ns
	raise FormatError.new('Unknown namespace qualifier: ' << $1)
      end
    elsif $1
      ns = @default_namespace
      name = $1
    end
    if !name
      raise FormatError.new("Illegal element format: #{ elem }")
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
