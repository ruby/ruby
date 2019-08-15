require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'fixtures/strings'
require_relative 'shared/each_document'

ruby_version_is ''...'2.5' do
  describe "YAML.load_documents" do
    it_behaves_like :yaml_each_document, :load_documents
  end
end
