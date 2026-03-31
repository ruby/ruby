#!/usr/bin/env ruby
# Add GitHub pull request reference / author info to git notes.

require 'net/http'
require 'uri'
require 'tmpdir'
require 'json'
require 'yaml'

# Conversion for people whose GitHub account name and SVN_ACCOUNT_NAME are different.
GITHUB_TO_SVN = {
  'amatsuda'    => 'a_matsuda',
  'matzbot'     => 'git',
  'jeremyevans' => 'jeremy',
  'znz'         => 'kazu',
  'k-tsj'       => 'ktsj',
  'nurse'       => 'naruse',
  'ioquatix'    => 'samuel',
  'suketa'      => 'suke',
  'unak'        => 'usa',
}

EMAIL_YML_URL = 'https://raw.githubusercontent.com/ruby/git.ruby-lang.org/refs/heads/master/config/email.yml'
SVN_TO_EMAILS = YAML.safe_load(Net::HTTP.get_response(URI(EMAIL_YML_URL)).tap(&:value).body)

class GitHub
  ENDPOINT = URI.parse('https://api.github.com')

  def initialize(access_token)
    @access_token = access_token
  end

  # https://developer.github.com/changes/2019-04-11-pulls-branches-for-commit/
  def pulls(owner:, repo:, commit_sha:)
    resp = get("/repos/#{owner}/#{repo}/commits/#{commit_sha}/pulls", accept: 'application/vnd.github.groot-preview+json')
    JSON.parse(resp.body)
  end

  # https://developer.github.com/v3/pulls/#get-a-single-pull-request
  def pull_request(owner:, repo:, number:)
    resp = get("/repos/#{owner}/#{repo}/pulls/#{number}")
    JSON.parse(resp.body)
  end

  # https://developer.github.com/v3/users/#get-a-single-user
  def user(username:)
    resp = get("/users/#{username}")
    JSON.parse(resp.body)
  end

  private

  def get(path, accept: 'application/vnd.github.v3+json')
    Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: ENDPOINT.scheme == 'https') do |http|
      headers = { 'Accept': accept, 'Authorization': "bearer #{@access_token}" }
      http.get(path, headers).tap(&:value)
    end
  end
end

module Git
  class << self
    def abbrev_ref(refname, repo_path:)
      git('rev-parse', '--symbolic', '--abbrev-ref', refname, repo_path: repo_path).strip
    end

    def rev_list(arg, first_parent: false, repo_path: nil)
      git('rev-list', *[('--first-parent' if first_parent)].compact, arg, repo_path: repo_path).lines.map(&:chomp)
    end

    def commit_message(sha)
      git('log', '-1', '--pretty=format:%B', sha)
    end

    def notes_message(sha)
      git('log', '-1', '--pretty=format:%N', sha)
    end

    def committer_name(sha)
      git('log', '-1', '--pretty=format:%cn', sha)
    end

    def committer_email(sha)
      git('log', '-1', '--pretty=format:%cE', sha)
    end

    private

    def git(*cmd, repo_path: nil)
      env = {}
      if repo_path
        env['GIT_DIR'] = repo_path
      end
      out = IO.popen(env, ['git', *cmd], &:read)
      unless $?.success?
        abort "Failed to execute: git #{cmd.join(' ')}\n#{out}"
      end
      out
    end
  end
end

github = GitHub.new(ENV.fetch('GITHUB_TOKEN'))

repo_path, *rest = ARGV
rest.each_slice(3).map do |oldrev, newrev, _refname|
  system('git', 'fetch', 'origin', 'refs/notes/commits:refs/notes/commits', exception: true)

  updated = false
  Git.rev_list("#{oldrev}..#{newrev}", first_parent: true).each do |sha|
    github.pulls(owner: 'ruby', repo: 'ruby', commit_sha: sha).each do |pull|
      number = pull.fetch('number')
      url = pull.fetch('html_url')
      next unless url.start_with?('https://github.com/ruby/ruby/pull/')

      # "Merged" notes for "Squash and merge"
      message = Git.commit_message(sha)
      notes = Git.notes_message(sha)
      if !message.include?(url) && !message.match(/[ (]##{number}[) ]/) && !notes.include?(url)
        system('git', 'notes', 'append', '-m', "Merged: #{url}", sha, exception: true)
        updated = true
      end

      # "Merged-By" notes for "Rebase and merge"
      if Git.committer_name(sha) == 'GitHub' && Git.committer_email(sha) == 'noreply@github.com'
        username = github.pull_request(owner: 'ruby', repo: 'ruby', number: number).fetch('merged_by').fetch('login')
        email = github.user(username: username).fetch('email')
        email ||= SVN_TO_EMAILS[GITHUB_TO_SVN.fetch(username, username)]&.first
        system('git', 'notes', 'append', '-m', "Merged-By: #{username}#{(" <#{email}>" if email)}", sha, exception: true)
        updated = true
      end
    end
  end

  if updated
    system('git', 'push', 'origin', 'refs/notes/commits', exception: true)
  end
end
