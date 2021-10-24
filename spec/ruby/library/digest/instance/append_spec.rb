require_relative '../../../spec_helper'
require 'digest'
require_relative 'shared/update'

describe "Digest::Instance#<<" do
  it_behaves_like :digest_instance_update, :<<
end
