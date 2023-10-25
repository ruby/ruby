require 'mspec/runner/mspec'

# Holds some of the state of the example (i.e. +it+ block) that is
# being evaluated. See also +ContextState+.
class ExampleState
  attr_reader :context, :it, :example

  def initialize(context, it, example = nil)
    @context = context
    @it = it
    @example = example
  end

  def context=(context)
    @description = nil
    @context = context
  end

  def describe
    @context.description
  end

  def description
    @description ||= "#{describe} #{@it}"
  end

  def filtered?
    incl = MSpec.include
    excl = MSpec.exclude
    included   = incl.empty? || incl.any? { |f| f === description }
    included &&= excl.empty? || !excl.any? { |f| f === description }
    !included
  end
end
