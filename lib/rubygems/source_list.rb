require 'rubygems/source'

class Gem::SourceList
  def initialize
    @sources = []
  end

  attr_reader :sources

  def self.from(ary)
    list = new

    if ary
      ary.each do |x|
        list << x
      end
    end

    return list
  end

  def initialize_copy(other)
    @sources = @sources.dup
  end

  def <<(obj)
    src = case obj
          when URI
            Gem::Source.new(obj)
          when Gem::Source
            obj
          else
            Gem::Source.new(URI.parse(obj))
          end

    @sources << src
    src
  end

  def replace(other)
    @sources.clear

    other.each do |x|
      self << x
    end

    self
  end

  def each
    @sources.each { |s| yield s.uri.to_s }
  end

  def each_source(&b)
    @sources.each(&b)
  end

  def ==(other)
    to_a == other
  end

  def to_a
    @sources.map { |x| x.uri.to_s }
  end

  alias_method :to_ary, :to_a

  def first
    @sources.first
  end

  def include?(other)
    if other.kind_of? Gem::Source
      @sources.include? other
    else
      @sources.find { |x| x.uri.to_s == other.to_s }
    end
  end

  def delete(uri)
    if uri.kind_of? Gem::Source
      @sources.delete uri
    else
      @sources.delete_if { |x| x.uri.to_s == uri.to_s }
    end
  end
end
