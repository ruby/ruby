#!/usr/bin/env ruby

require "bundler/inline"
require "json"
require "net/http"
require "set"
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
    abort "usage: #{File.basename($0)} FROM [--update]"
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
  if arg.downcase == "news"
    body = read_local_news_md
  else
    uri = URI.parse(arg)
    body = Net::HTTP.get(uri)
  end

  parse_stdlib_versions_from_news(body)
end

def read_local_news_md
  news_path = File.join(__dir__, "..", "NEWS.md")
  unless File.exist?(news_path)
    abort "NEWS.md not found at #{news_path}"
  end
  File.read(news_path)
end

def parse_stdlib_versions_from_news(body)
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

def resolve_repo(name)
  case name
  when "minitest"
    { repo: name, org: "minitest" }
  when "test-unit"
    { repo: name, org: "test-unit" }
  when "bundler"
    { repo: "rubygems", org: "ruby" }
  else
    { repo: name, org: "ruby" }
  end
end

def fetch_release_range(name, from_version, to_version, org, repo)
  releases = []
  Octokit.releases("#{org}/#{repo}").each do |release|
    releases << release.tag_name
  end

  # Keep only version-like tags and sort ascending by semantic version
  releases = releases.select { |t| t =~ /^v\d/ || t =~ /^\d/ || t =~ /^bundler-\d/ }
  releases = releases.sort_by { |t| Gem::Version.new(t.sub(/^bundler-/, "").sub(/^v/, "").tr("_", ".")) }

  start_index = releases.index("v#{from_version}") || releases.index(from_version) || releases.index("bundler-v#{from_version}")
  end_index = releases.index("v#{to_version}") || releases.index(to_version) || releases.index("bundler-v#{to_version}")
  return nil unless start_index && end_index

  range = releases[start_index + 1..end_index]
  return nil if range.nil? || range.empty?

  range
end

def collect_gem_updates(versions_from, versions_to)
  results = []

  versions_to.each do |name, version|
    # Skip items which do not exist in the FROM map to reduce API calls
    next unless versions_from.key?(name)
    next if name == "RubyGems" || name == "bundler"

    info = resolve_repo(name)
    org = info[:org]
    repo = info[:repo]

    release_range = fetch_release_range(name, versions_from[name], version, org, repo)
    next unless release_range

    footnote_links = []
    release_range.each do |rel|
      footnote_links << {
        ref: "#{name}-#{rel.sub(/^bundler-/, '')}",
        url: "https://github.com/#{org}/#{repo}/releases/tag/#{rel}",
        tag: rel.sub(/^bundler-/, ''),
      }
    end

    results << {
      name: name,
      version: version,
      from_version: versions_from[name],
      release_range: release_range,
      footnote_links: footnote_links,
    }
  end

  results
end

def print_results(results)
  footnote_lines = []

  results.each do |r|
    puts "* #{r[:name]} #{r[:version]}"
    links = r[:release_range].map { |rel|
      "[#{rel.sub(/^bundler-/, '')}][#{r[:name]}-#{rel.sub(/^bundler-/, '')}]"
    }
    puts "  * #{r[:from_version]} to #{links.join(', ')}"
    r[:footnote_links].each do |fl|
      footnote_lines << "[#{fl[:ref]}]: #{fl[:url]}"
    end
  end

  puts footnote_lines.join("\n")
end

def update_news_md(results)
  news_path = File.join(__dir__, "..", "NEWS.md")
  unless File.exist?(news_path)
    abort "NEWS.md not found at #{news_path}"
  end
  content = File.read(news_path)
  lines = content.lines

  # Build a lookup: gem name => result
  result_by_name = {}
  results.each { |r| result_by_name[r[:name]] = r }

  new_lines = []
  i = 0
  while i < lines.length
    line = lines[i]

    # Check if this line is a gem bullet like "* gemname x.y.z"
    if line =~ /^\* ([A-Za-z0-9_\-]+)\s+(\d+(?:\.\d+){0,3})\b/
      gem_name = $1
      gem_name_normalized = gem_name == "RubyGems" ? "RubyGems" : gem_name

      new_lines << line

      if result_by_name.key?(gem_name_normalized)
        r = result_by_name[gem_name_normalized]

        # Skip any existing sub-bullet lines that follow (lines starting with spaces + *)
        while i + 1 < lines.length && lines[i + 1] =~ /^\s+\*/
          i += 1
        end

        # Insert the version diff sub-bullet
        links = r[:release_range].map { |rel|
          "[#{rel.sub(/^bundler-/, '')}][#{r[:name]}-#{rel.sub(/^bundler-/, '')}]"
        }
        sub_bullet = "  * #{r[:from_version]} to #{links.join(', ')}\n"
        new_lines << sub_bullet
      end
    else
      new_lines << line
    end
    i += 1
  end

  # Collect all new footnote links
  all_footnotes = []
  results.each do |r|
    r[:footnote_links].each do |fl|
      all_footnotes << "[#{fl[:ref]}]: #{fl[:url]}"
    end
  end

  # Remove any existing footnote links that we are about to add (avoid duplicates)
  existing_refs = Set.new(all_footnotes.map { |f| f[/^\[([^\]]+)\]:/, 1] })
  new_lines = new_lines.reject do |line|
    if line =~ /^\[([^\]]+)\]:\s+https:\/\/github\.com\//
      existing_refs.include?($1)
    else
      false
    end
  end

  # Ensure the file ends with a newline before adding footnotes
  unless new_lines.last&.end_with?("\n")
    new_lines << "\n"
  end

  # Append footnote links at the end of the file
  all_footnotes.each do |footnote|
    new_lines << "#{footnote}\n"
  end

  File.write(news_path, new_lines.join)
  puts "Updated #{news_path} with #{results.length} gem update entries and #{all_footnotes.length} footnote links."
end

# --- Main ---

update_mode = ARGV.delete("--update")

versions_from = load_versions(ARGV[0])
versions_to = load_versions("news")

results = collect_gem_updates(versions_from, versions_to)

print_results(results)

if update_mode
  update_news_md(results)
end
