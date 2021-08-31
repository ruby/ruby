require 'mspec/runner/actions/filter'

# TagAction - Write tagged spec description string to a
# tag file associated with each spec file.
#
# The action is triggered by specs whose descriptions
# match the filter created with 'tags' and/or 'desc'
#
# The action fires in the :after event, after the spec
# had been run. The action fires if the outcome of
# running the spec matches 'outcome'.
#
# The arguments are:
#
#   action:  :add, :del
#   outcome: :pass, :fail, :all
#   tag:     the tag to create/delete
#   comment: the comment to create
#   tags:    zero or more tags to get matching
#            spec description strings from
#   desc:    zero or more strings to match the
#            spec description strings

class TagAction < ActionFilter
  def initialize(action, outcome, tag, comment, tags = nil, descs = nil)
    super tags, descs
    @action = action
    @outcome = outcome
    @tag = tag
    @comment = comment
    @report = []
    @exception = false
  end

  # Returns true if there are no _tag_ or _description_ filters. This
  # means that a TagAction matches any example by default. Otherwise,
  # returns true if either the _tag_ or the _description_ filter
  # matches +string+.
  def ===(string)
    return true unless @sfilter or @tfilter
    @sfilter === string or @tfilter === string
  end

  # Callback for the MSpec :before event. Resets the +#exception?+
  # flag to false.
  def before(state)
    @exception = false
  end

  # Callback for the MSpec :exception event. Sets the +#exception?+
  # flag to true.
  def exception(exception)
    @exception = true
  end

  # Callback for the MSpec :after event. Performs the tag action
  # depending on the type of action and the outcome of evaluating
  # the example. See +TagAction+ for a description of the actions.
  def after(state)
    if self === state.description and outcome?
      tag = SpecTag.new
      tag.tag = @tag
      tag.comment = @comment
      tag.description = state.description

      case @action
      when :add
        changed = MSpec.write_tag tag
      when :del
        changed = MSpec.delete_tag tag
      end

      @report << state.description if changed
    end
  end

  # Returns true if the result of evaluating the example matches
  # the _outcome_ registered for this tag action. See +TagAction+
  # for a description of the _outcome_ types.
  def outcome?
    @outcome == :all or
        (@outcome == :pass and not exception?) or
        (@outcome == :fail and exception?)
  end

  # Returns true if an exception was raised while evaluating the
  # current example.
  def exception?
    @exception
  end

  def report
    @report.join("\n") + "\n"
  end
  private :report

  # Callback for the MSpec :finish event. Prints the actions
  # performed while evaluating the examples.
  def finish
    case @action
    when :add
      if @report.empty?
        print "\nTagAction: no specs were tagged with '#{@tag}'\n"
      else
        print "\nTagAction: specs tagged with '#{@tag}':\n\n"
        print report
      end
    when :del
      if @report.empty?
        print "\nTagAction: no tags '#{@tag}' were deleted\n"
      else
        print "\nTagAction: tag '#{@tag}' deleted for specs:\n\n"
        print report
      end
    end
  end

  def register
    super
    MSpec.register :before,    self
    MSpec.register :exception, self
    MSpec.register :after,     self
    MSpec.register :finish,    self
  end

  def unregister
    super
    MSpec.unregister :before,    self
    MSpec.unregister :exception, self
    MSpec.unregister :after,     self
    MSpec.unregister :finish,    self
  end
end
