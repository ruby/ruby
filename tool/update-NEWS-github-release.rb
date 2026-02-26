#!/usr/bin/env ruby

require "bundler/inline"
require "json"
require "net/http"
require "uri"

gemfile do
  source "https://rubygems.org"
  gem "octokit"
  gem "faraday-retry"
end

Octokit.configure do |c|
  c.access_token = ENV["GITHUB_TOKEN"]
  c.auto_paginate = true
  c.per_page = 100
end

# Build a gem=>version map from stdgems.org stdgems.json for a given Ruby version (e.g., "3.4")
def fetch_default_gems_versions(ruby_version)
  uri = URI.parse("https://stdgems.org/stdgems.json")
  json = JSON.parse(Net::HTTP.get(uri))
  gems = json["gems"] || []

  map = {}
  gems.each do |g|
    # Only include default gems (skip ones marked removed)
    next if g["removed"]
    versions = g["versions"] || {}

    # versions has "default" and "bundled" keys, each containing Ruby version => version mappings
    selected_version = nil
    
    # Try both "default" and "bundled" categories
    ["default", "bundled"].each do |category|
      category_versions = versions[category] || {}
      next if selected_version
      
      if category_versions.key?(ruby_version)
        selected_version = category_versions[ruby_version]
      else
        # Fall back to the highest patch version matching the given major.minor
        major_minor = /^#{Regexp.escape(ruby_version)}\./
        candidates = category_versions.select { |k, _| k.match?(major_minor) }
        if !candidates.empty?
          # Sort keys as Gem::Version to pick the highest patch
          selected_version = candidates.sort_by { |k, _| Gem::Version.new(k) }.last[1]
        end
      end
    end
    
    next unless selected_version

    name = g["gem"]
    # Normalize name to match existing special cases
    name = "RubyGems" if name == "rubygems"
    map[name] = selected_version
  end

  map
end

# Load gem=>version map from a file or from stdgems.org if a Ruby version is given.
def load_versions(arg)
  if arg.nil?
    abort "usage: #{File.basename($0)} FROM TO (each can be a file path or Ruby version like 3.4)"
  end
  if File.exist?(arg)
    File.readlines(arg).map(&:split).to_h
  elsif arg.match?(/^\d+\.\d+(?:\.\d+)?$/)
    fetch_default_gems_versions(arg)
  elsif arg.downcase == "news" || arg =~ %r{https?://.*/NEWS\.md}
    fetch_versions_to_from_news(arg)
  else
    abort "Invalid argument: #{arg}. Provide a file path or a Ruby version (e.g., 3.4)."
  end
end

# Build a gem=>version map by parsing the "## Stdlib updates" section from Ruby's NEWS.md
def fetch_versions_to_from_news(arg)
  url = arg.downcase == "news" ? "https://raw.githubusercontent.com/ruby/ruby/refs/heads/master/NEWS.md" : arg
  uri = URI.parse(url)
  body = Net::HTTP.get(uri)

  # Extract the Stdlib updates section
  start_idx = body.index(/^## Stdlib updates$/)
  unless start_idx
    # Try a more lenient search if anchors differ
    start_idx = body.index("## Stdlib\nupdates") || body.index("## Stdlib updates")
  end
  abort "Stdlib updates section not found in NEWS.md" unless start_idx

  section = body[start_idx..-1]
  # Stop at the next top-level section header (skip the current header line)
  first_line_len = section.lines.first ? section.lines.first.length : 0
  stop_idx = section.index(/^##\s+/, first_line_len)
  section = stop_idx ? section[0...stop_idx] : section

  map = {}

  # Normalize lines and collect bullet entries like: "* gemname x.y.z"
  section.each_line do |line|
    line = line.strip
    next unless line.start_with?("*")
    # Remove leading bullet
    entry = line.sub(/^\*\s+/, "")

    # Some lines can include descriptions or links; we only take simple "name version"
    # Accept names with hyphens/underscores and versions like 1.2.3 or 1.2.3.4
    if entry =~ /^([A-Za-z0-9_\-]+)\s+(\d+(?:\.\d+){0,3})\b/
      name = $1
      ver = $2
      name = "RubyGems" if name.downcase == "rubygems"
      map[name] = ver
    end
  end

  map
end

versions_from = load_versions(ARGV[0])
versions_to = load_versions("news")
footnote_link = []

versions_to.each do |name, version|
  # Skip items which do not exist in the FROM map to reduce API calls
  next unless versions_from.key?(name)
  next if name == "RubyGems" || name == "bundler"

  releases = []

  case name
  when "minitest"
    repo = name
    org = "minitest"
  when "test-unit"
    repo = name
    org = "test-unit"
  when "bundler"
    repo = "rubygems"
    org = "ruby"
  else
    repo = name
    org = "ruby"
  end

  Octokit.releases("#{org}/#{repo}").each do |release|
    releases << release.tag_name
  end

  # Keep only version-like tags and sort descending by semantic version
  releases = releases.select { |t| t =~ /^v\d/ || t =~ /^\d/ || t =~ /^bundler-\d/ }
  releases = releases.sort_by { |t| Gem::Version.new(t.sub(/^bundler-/, "").sub(/^v/, "").tr("_", ".")) }

  start_index = releases.index("v#{versions_from[name]}") || releases.index(versions_from[name]) || releases.index("bundler-v#{versions_from[name]}")
  end_index = releases.index("v#{versions_to[name]}") || releases.index(versions_to[name]) || releases.index("bundler-v#{versions_to[name]}")
  release_range = releases[start_index+1..end_index] if start_index && end_index

  next unless release_range
  next if release_range.empty?

  puts "* #{name} #{version}"
  puts "  * #{versions_from[name]} to #{release_range.map { |rel|
 "[#{rel.sub(/^bundler-/, '')}][#{name}-#{rel.sub(/^bundler-/, '')}]"}.join(", ")}"
  release_range.each do |rel|
    footnote_link << "[#{name}-#{rel.sub(/^bundler-/, '')}]: https://github.com/#{org}/#{repo}/releases/tag/#{rel}"
  end
end

puts footnote_link.join("\n")
