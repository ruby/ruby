require_relative '../../spec_helper'
require_relative 'shared/valid_jd'
require 'date'

ruby_version_is ''...'2.7' do
  describe "Date.valid_jd?" do

    it_behaves_like :date_valid_jd?, :valid_jd?

  end
end
