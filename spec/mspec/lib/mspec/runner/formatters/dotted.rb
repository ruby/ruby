require 'mspec/runner/formatters/base'

class DottedFormatter < BaseFormatter
  def register
    super
    MSpec.register :after, self
  end

  # Callback for the MSpec :after event. Prints an indicator
  # for the result of evaluating this example as follows:
  #   . = No failure or error
  #   F = An SpecExpectationNotMetError was raised
  #   E = Any exception other than SpecExpectationNotMetError
  def after(state = nil)
    super(state)

    if exception?
      print failure? ? "F" : "E"
    else
      print "."
    end
  end
end
