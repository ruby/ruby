# frozen_string_literal: true
require 'rubygems/test_case'

class TestRemoteFetchError < Gem::TestCase
  def test_password_redacted
    error = Gem::RemoteFetcher::FetchError.new('There was an error fetching', 'https://user:secret@gemsource.org')
    refute_match 'secret', error.to_s
  end

  def test_invalid_url
    error = Gem::RemoteFetcher::FetchError.new('There was an error fetching', 'https://::gemsource.org')
    assert_equal error.to_s, 'There was an error fetching (https://::gemsource.org)'
  end

  def test_to_s
    error = Gem::RemoteFetcher::FetchError.new('There was an error fetching', 'https://gemsource.org')
    assert_equal error.to_s, 'There was an error fetching (https://gemsource.org)'
  end
end
