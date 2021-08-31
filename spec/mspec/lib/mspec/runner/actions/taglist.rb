require 'mspec/runner/actions/filter'

# TagListAction - prints out the descriptions for any specs
# tagged with +tags+. If +tags+ is an empty list, prints out
# descriptions for any specs that are tagged.
class TagListAction
  def initialize(tags = nil)
    @tags = tags.nil? || tags.empty? ? nil : Array(tags)
    @filter = nil
  end

  # Returns true. This enables us to match any tag when loading
  # tags from the file.
  def include?(arg)
    true
  end

  # Returns true if any tagged descriptions matches +string+.
  def ===(string)
    @filter === string
  end

  # Prints a banner about matching tagged specs.
  def start
    if @tags
      print "\nListing specs tagged with #{@tags.map { |t| "'#{t}'" }.join(", ") }\n\n"
    else
      print "\nListing all tagged specs\n\n"
    end
  end

  # Creates a MatchFilter for specific tags or for all tags.
  def load
    @filter = nil
    desc = MSpec.read_tags(@tags || self).map { |t| t.description }
    @filter = MatchFilter.new(nil, *desc) unless desc.empty?
  end

  # Prints the spec description if it matches the filter.
  def after(state)
    return unless self === state.description
    print state.description, "\n"
  end

  def register
    MSpec.register :start, self
    MSpec.register :load,  self
    MSpec.register :after, self
  end

  def unregister
    MSpec.unregister :start, self
    MSpec.unregister :load,  self
    MSpec.unregister :after, self
  end
end
