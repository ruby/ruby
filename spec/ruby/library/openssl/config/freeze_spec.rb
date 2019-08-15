require_relative '../../../spec_helper'
require_relative '../shared/constants'

require 'openssl'

describe "OpenSSL::Config#freeze" do
  it "needs to be reviewed for completeness"

  it "freezes" do
    c = OpenSSL::Config.new
    -> {
      c['foo'] = [ ['key', 'value'] ]
    }.should_not raise_error
    c.freeze
    c.frozen?.should be_true
    -> {
      c['foo'] = [ ['key', 'value'] ]
    }.should raise_error(TypeError)
  end
end
