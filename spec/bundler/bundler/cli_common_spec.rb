# frozen_string_literal: true

require "bundler/cli"

RSpec.describe Bundler::CLI::Common do
  describe "gem_not_found_message" do
    it "should suggest alternate gem names" do
      message = subject.gem_not_found_message("ralis", ["BOGUS"])
      expect(message).to match("Could not find gem 'ralis'.$")
      message = subject.gem_not_found_message("ralis", ["rails"])
      expect(message).to match("Did you mean 'rails'?")
      message = subject.gem_not_found_message("Rails", ["rails"])
      expect(message).to match("Did you mean 'rails'?")
      message = subject.gem_not_found_message("meail", %w[email fail eval])
      expect(message).to match("Did you mean 'email'?")
      message = subject.gem_not_found_message("nokogri", %w[nokogiri rails sidekiq dog])
      expect(message).to match("Did you mean 'nokogiri'?")
      message = subject.gem_not_found_message("methosd", %w[method methods bogus])
      expect(message).to match("Did you mean 'methods' or 'method'?")
    end
  end
end
