require 'spec_helper'
require 'mspec/utils/deprecate'

describe MSpec, "#deprecate" do
  it "warns when using a deprecated method" do
    warning = nil
    $stderr.stub(:puts) { |str| warning = str }
    MSpec.deprecate(:some_method, :other_method)
    warning.should start_with(<<-EOS.chomp)

some_method is deprecated, use other_method instead.
from
EOS
    warning.should include(__FILE__)
    warning.should include('8')
  end
end
