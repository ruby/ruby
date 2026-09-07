# frozen_string_literal: true

require "bundler/compact_index_client"
require "bundler/compact_index_client/cache"
require "tmpdir"

RSpec.describe Bundler::CompactIndexClient::Cache do
  let(:directory) { Pathname.new(Dir.mktmpdir("compact_index")) }
  let(:cache) { described_class.new(directory) }

  it "rejects a gem name that would escape the cache directory" do
    expect { cache.info("../../../../pwn") }.to raise_error(Bundler::SecurityError, /malformed gem name/)
  end

  it "accepts plain gem names, including special characters" do
    expect { cache.info("rack") }.not_to raise_error
    expect { cache.info("Rails.js") }.not_to raise_error
  end
end
