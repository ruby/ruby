require 'mspec/runner/filters/match'

# ActionFilter is a base class for actions that are triggered by
# specs that match the filter. The filter may be specified by
# strings that match spec descriptions or by tags for strings
# that match spec descriptions.
#
# Unlike TagFilter and RegexpFilter, ActionFilter instances do
# not affect the specs that are run. The filter is only used to
# trigger the action.

class ActionFilter
  def initialize(tags=nil, descs=nil)
    @tags = Array(tags)
    descs = Array(descs)
    @sfilter = descs.empty? ? nil : MatchFilter.new(nil, *descs)
    @tfilter = nil
  end

  def ===(string)
    @sfilter === string or @tfilter === string
  end

  def load
    return if @tags.empty?

    desc = MSpec.read_tags(@tags).map { |t| t.description }
    return if desc.empty?

    @tfilter = MatchFilter.new(nil, *desc)
  end

  def register
    MSpec.register :load, self
  end

  def unregister
    MSpec.unregister :load, self
  end
end
