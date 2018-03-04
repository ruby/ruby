require_relative '../../../spec_helper'
require_relative 'shared/constants'
require_relative 'shared/update'

describe "Digest::MD5#<<" do
 it_behaves_like :md5_update, :<<
end
