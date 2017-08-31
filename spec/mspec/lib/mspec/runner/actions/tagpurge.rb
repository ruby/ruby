require 'mspec/runner/actions/filter'
require 'mspec/runner/actions/taglist'

# TagPurgeAction - removes all tags not matching any spec
# descriptions.
class TagPurgeAction < TagListAction
  attr_reader :matching

  def initialize
    @matching = []
    @filter   = nil
    @tags     = nil
  end

  # Prints a banner about purging tags.
  def start
    print "\nRemoving tags not matching any specs\n\n"
  end

  # Creates a MatchFilter for all tags.
  def load
    @filter = nil
    @tags = MSpec.read_tags self
    desc = @tags.map { |t| t.description }
    @filter = MatchFilter.new(nil, *desc) unless desc.empty?
  end

  # Saves any matching tags
  def after(state)
    @matching << state.description if self === state.description
  end

  # Rewrites any matching tags. Prints non-matching tags.
  # Deletes the tag file if there were no tags (this cleans
  # up empty or malformed tag files).
  def unload
    if @filter
      matched = @tags.select { |t| @matching.any? { |s| s == t.description } }
      MSpec.write_tags matched

      (@tags - matched).each { |t| print t.description, "\n" }
    else
      MSpec.delete_tags
    end
  end

  def register
    super
    MSpec.register :unload, self
  end

  def unregister
    super
    MSpec.unregister :unload, self
  end
end
