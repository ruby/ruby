#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require_relative './sync_default_gems'

class GitHubAPIClient
  def initialize(token)
    @token = token
  end

  def get(path)
    response = Net::HTTP.get_response(URI("https://api.github.com#{path}"), {
      'Authorization' => "token #{@token}",
      'Accept' => 'application/vnd.github.v3+json',
    }).tap(&:value)
    JSON.parse(response.body, symbolize_names: true)
  end

  def post(path, body = {})
    body = JSON.dump(body)
    response = Net::HTTP.post(URI("https://api.github.com#{path}"), body, {
      'Authorization' => "token #{@token}",
      'Accept' => 'application/vnd.github.v3+json',
      'Content-Type' => 'application/json',
    }).tap(&:value)
    JSON.parse(response.body, symbolize_names: true)
  end
end

class AutoReviewPR
  REPO = 'ruby/ruby'

  COMMENT_USER = 'github-actions[bot]'
  COMMENT_PREFIX = 'The following files are maintained in the following upstream repositories:'
  COMMENT_SUFFIX = 'Please file a pull request to the above instead. Thank you!'

  def initialize(client)
    @client = client
  end

  def review(pr_number)
    # Fetch the list of files changed by the PR
    changed_files = @client.get("/repos/#{REPO}/pulls/#{pr_number}/files").map { it.fetch(:filename) }

    # Build a Hash: { upstream_repo => files, ... }
    upstream_repos = SyncDefaultGems::Repository.group(changed_files)
    upstream_repos.delete(nil) # exclude no-upstream files
    upstream_repos.delete('prism') if changed_files.include?('prism_compile.c') # allow prism changes in this case
    if upstream_repos.empty?
      puts "Skipped: The PR ##{pr_number} doesn't have upstream repositories."
      return
    end

    # Check if the PR is already reviewed
    existing_comments = @client.get("/repos/#{REPO}/issues/#{pr_number}/comments")
    existing_comments.map! { [it.fetch(:user).fetch(:login), it.fetch(:body)] }
    if existing_comments.any? { |user, comment| user == COMMENT_USER && comment.start_with?(COMMENT_PREFIX) }
      puts "Skipped: The PR ##{pr_number} already has an automated review comment."
      return
    end

    # Post a comment
    comment = format_comment(upstream_repos)
    result = @client.post("/repos/#{REPO}/issues/#{pr_number}/comments", { body: comment })
    puts "Success: #{JSON.pretty_generate(result)}"
  end

  private

  # upstream_repos: { upstream_repo => files, ... }
  def format_comment(upstream_repos)
    comment = +''
    comment << "#{COMMENT_PREFIX}\n\n"

    upstream_repos.each do |upstream_repo, files|
      comment << "* https://github.com/ruby/#{upstream_repo}\n"
      files.each do |file|
        comment << "    * #{file}\n"
      end
    end

    comment << "\n#{COMMENT_SUFFIX}"
    comment
  end
end

pr_number = ARGV[0] || abort("Usage: #{$0} <pr_number>")
client = GitHubAPIClient.new(ENV.fetch('GITHUB_TOKEN'))

AutoReviewPR.new(client).review(pr_number)
