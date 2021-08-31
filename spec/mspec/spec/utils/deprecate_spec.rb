require 'spec_helper'
require 'mspec/utils/deprecate'

RSpec.describe MSpec, "#deprecate" do
  it "warns when using a deprecated method" do
    warning = nil
    allow($stderr).to receive(:puts) { |str| warning = str }
    MSpec.deprecate(:some_method, :other_method)
    expect(warning).to start_with(<<-EOS.chomp)

some_method is deprecated, use other_method instead.
from
EOS
    expect(warning).to include(__FILE__)
    expect(warning).to include('8')
  end
end
