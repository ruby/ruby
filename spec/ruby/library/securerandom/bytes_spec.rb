require_relative '../../spec_helper'
require_relative '../../core/random/shared/bytes'

require 'securerandom'

describe "SecureRandom.bytes" do
  it_behaves_like :random_bytes, :bytes, SecureRandom
end
