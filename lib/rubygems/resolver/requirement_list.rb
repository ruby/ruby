##
# The RequirementList is used to hold the requirements being considered
# while resolving a set of gems.
#
# The RequirementList acts like a queue where the oldest items are removed
# first.

class Gem::Resolver::RequirementList

  include Enumerable

  ##
  # Creates a new RequirementList.

  def initialize
    @list = []
  end

  def initialize_copy other # :nodoc:
    @list = @list.dup
  end

  ##
  # Adds Resolver::DependencyRequest +req+ to this requirements list.

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

  ##
  # Is the list empty?

  def empty?
    @list.empty?
  end

  ##
  # Remove the oldest DependencyRequest from the list.

  def remove
    @list.shift
  end

  ##
  # Returns the oldest five entries from the list.

  def next5
    @list[0,5]
  end
end
