require 'mspec/expectations/expectations'
require 'mspec/runner/formatters/dotted'

class SummaryFormatter < DottedFormatter
  # Callback for the MSpec :after event. Overrides the
  # callback provided by +DottedFormatter+ and does not
  # print any output for each example evaluated.
  def after(state)
    # do nothing
  end
end
