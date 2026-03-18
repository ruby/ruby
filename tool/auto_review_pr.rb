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

  UPSTREAM_COMMENT_PREFIX = 'The following files are maintained in the following upstream repositories:'
  UPSTREAM_COMMENT_SUFFIX = 'Please file a pull request to the above instead. Thank you!'

  FORK_COMMENT_PREFIX = 'It looks like this pull request was filed from a branch in ruby/ruby.'
  FORK_COMMENT_BODY = <<~COMMENT
    #{FORK_COMMENT_PREFIX}

    Since ruby/ruby is bi-directionally mirrored with the official git repository at git.ruby-lang.org, \
    having topic branches in ruby/ruby makes it harder to manage the mirror.

    Could you please close this pull request and re-file it from a branch in your personal fork instead? \
    You can fork https://github.com/ruby/ruby, push your branch there, and open a new pull request from it.

    Thank you for your contribution!
  COMMENT

  def initialize(client)
    @client = client
  end

  def review(pr_number)
    existing_comments = fetch_existing_comments(pr_number)
    review_non_fork_branch(pr_number, existing_comments)
    review_upstream_repos(pr_number, existing_comments)
  end

  private

  def fetch_existing_comments(pr_number)
    comments = @client.get("/repos/#{REPO}/issues/#{pr_number}/comments")
    comments.map { [it.fetch(:user).fetch(:login), it.fetch(:body)] }
  end

  def already_commented?(existing_comments, prefix)
    existing_comments.any? { |user, comment| user == COMMENT_USER && comment.start_with?(prefix) }
  end

  def post_comment(pr_number, comment)
    result = @client.post("/repos/#{REPO}/issues/#{pr_number}/comments", { body: comment })
    puts "Success: #{JSON.pretty_generate(result)}"
  end

  # Suggest re-filing from a fork if the PR branch is in ruby/ruby itself
  def review_non_fork_branch(pr_number, existing_comments)
    if already_commented?(existing_comments, FORK_COMMENT_PREFIX)
      puts "Skipped: The PR ##{pr_number} already has a fork branch comment."
      return
    end

    pr = @client.get("/repos/#{REPO}/pulls/#{pr_number}")
    head_repo = pr.dig(:head, :repo, :full_name)
    if head_repo != REPO
      puts "Skipped: The PR ##{pr_number} is already from a fork (#{head_repo})."
      return
    end

    post_comment(pr_number, FORK_COMMENT_BODY)
  end

  # Suggest filing PRs to upstream repositories for files that have one
  def review_upstream_repos(pr_number, existing_comments)
    if already_commented?(existing_comments, UPSTREAM_COMMENT_PREFIX)
      puts "Skipped: The PR ##{pr_number} already has an upstream repos comment."
      return
    end

    changed_files = @client.get("/repos/#{REPO}/pulls/#{pr_number}/files").map { it.fetch(:filename) }

    upstream_repos = SyncDefaultGems::Repository.group(changed_files)
    upstream_repos.delete(nil)
    upstream_repos.delete('prism') if changed_files.include?('prism_compile.c')
    if upstream_repos.empty?
      puts "Skipped: The PR ##{pr_number} doesn't have upstream repositories."
      return
    end

    post_comment(pr_number, format_upstream_comment(upstream_repos))
  end

  def format_upstream_comment(upstream_repos)
    comment = +''
    comment << "#{UPSTREAM_COMMENT_PREFIX}\n\n"

    upstream_repos.each do |upstream_repo, files|
      comment << "* https://github.com/ruby/#{upstream_repo}\n"
      files.each do |file|
        comment << "    * #{file}\n"
      end
    end

    comment << "\n#{UPSTREAM_COMMENT_SUFFIX}"
    comment
  end
end

pr_number = ARGV[0] || abort("Usage: #{$0} <pr_number>")
client = GitHubAPIClient.new(ENV.fetch('GITHUB_TOKEN'))

AutoReviewPR.new(client).review(pr_number)
