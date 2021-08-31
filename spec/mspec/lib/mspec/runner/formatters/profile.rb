require 'mspec/runner/formatters/dotted'
require 'mspec/runner/actions/profile'

class ProfileFormatter < DottedFormatter
  def initialize(out = nil)
    super(out)

    @describe_name = nil
    @describe_time = nil
    @describes = []
    @its = []
  end

  def register
    (@profile = ProfileAction.new).register
    super
  end
end
