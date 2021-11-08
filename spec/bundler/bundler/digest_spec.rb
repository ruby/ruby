# frozen_string_literal: true

require "digest"
require "bundler/digest"

RSpec.describe Bundler::Digest do
  context "SHA1" do
    subject { Bundler::Digest }
    let(:stdlib) { ::Digest::SHA1 }

    it "is compatible with stdlib" do
      ["foo", "skfjsdlkfjsdf", "3924m", "ldskfj"].each do |payload|
        expect(subject.sha1(payload)).to be == stdlib.hexdigest(payload)
      end
    end
  end
end
