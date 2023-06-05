# frozen_string_literal: true

require "openssl"
require "bundler/digest"

RSpec.describe Bundler::Digest do
  context "SHA1" do
    subject { Bundler::Digest }
    let(:stdlib) { OpenSSL::Digest::SHA1 }

    it "is compatible with stdlib" do
      random_strings = ["foo", "skfjsdlkfjsdf", "3924m", "ldskfj"]

      # https://datatracker.ietf.org/doc/html/rfc3174#section-7.3
      rfc3174_test_cases = ["abc", "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "a", "01234567" * 8]

      (random_strings + rfc3174_test_cases).each do |payload|
        sha1 = subject.sha1(payload)
        sha1_stdlib = stdlib.hexdigest(payload)
        expect(sha1).to be == sha1_stdlib, "#{payload}'s sha1 digest (#{sha1}) did not match stlib's result (#{sha1_stdlib})"
      end
    end
  end
end
