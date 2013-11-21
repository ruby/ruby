##
# Used internally to hold the requirements being considered
# while attempting to find a proper activation set.

class Gem::Resolver::RequirementList

  include Enumerable

  def initialize
    @list = []
  end

  def initialize_copy(other)
    @list = @list.dup
  end

  def add(req)
    @list.push req
    req
  end

  ##
  # Enumerates requirements in the list

  def each # :nodoc:
    return enum_for __method__ unless block_given?

    @list.each do |requirement|
      yield requirement
    end
  end

  def empty?
    @list.empty?
  end

  def remove
    @list.shift
  end

  def next5
    @list[0,5]
  end
end
