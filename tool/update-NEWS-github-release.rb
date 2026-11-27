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
  body = http_get(uri)
  json = JSON.parse(body)
  gems = json["gems"] || []

  # Prefer the initial release key (e.g. "4.0.0") over the rolling
  # major.minor key (e.g. "4.0") so the diff baseline reflects the original
  # X.Y.0 release rather than the latest patch level.
  initial_release_key = (ruby_version =~ /\A\d+\.\d+\z/) ? "#{ruby_version}.0" : nil

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

      if initial_release_key && category_versions.key?(initial_release_key)
        selected_version = category_versions[initial_release_key]
      elsif category_versions.key?(ruby_version)
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

def previous_ruby_version
  version_h = File.join(__dir__, "..", "include", "ruby", "version.h")
  major = minor = nil
  File.foreach(version_h) do |l|
    major = $1.to_i if l =~ /^\s*#\s*define\s+RUBY_API_VERSION_MAJOR\s+(\d+)/
    minor = $1.to_i if l =~ /^\s*#\s*define\s+RUBY_API_VERSION_MINOR\s+(\d+)/
  end
  abort "Cannot detect Ruby version from #{version_h}" unless major && minor
  minor > 0 ? "#{major}.#{minor - 1}" : "#{major - 1}.0"
end

# Load gem=>version map from a file or from stdgems.org if a Ruby version is given.
def load_versions(arg)
  arg ||= previous_ruby_version
  if File.exist?(arg)
    File.readlines(arg).map(&:split).to_h
  elsif arg.match?(/^\d+\.\d+(?:\.\d+)?$/)
    fetch_default_gems_versions(arg)
  elsif arg.downcase == "news" || arg =~ %r{https?://.*/NEWS\.md}
    fetch_versions_from_news(arg)
  else
    abort "Invalid argument: #{arg}. Provide a file path or a Ruby version (e.g., 3.4)."
  end
end

# Build a gem=>version map by parsing the "## Stdlib updates" section from Ruby's NEWS.md
def fetch_versions_from_news(arg)
  if arg.downcase == "news"
    body = read_local_news_md
  else
    body = http_get(URI.parse(arg))
  end

  parse_stdlib_versions_from_news(body)
end

# Fetch a URL with a clear abort message on network or HTTP failures.
# Used for sources whose absence makes the rest of the script meaningless.
def http_get(uri)
  res = Net::HTTP.get_response(uri)
  unless res.is_a?(Net::HTTPSuccess)
    abort "error: #{uri} returned HTTP #{res.code} #{res.message}"
  end
  res.body
rescue SystemCallError, SocketError, IOError, Net::HTTPError => e
  abort "error: failed to fetch #{uri}: #{e.class}: #{e.message}"
end

def read_local_news_md
  news_path = File.join(__dir__, "..", "NEWS.md")
  unless File.exist?(news_path)
    abort "NEWS.md not found at #{news_path}"
  end
  File.read(news_path)
end

# Build a gem=>version map from the current repository state. Default gems
# come from {ext,lib}/**/*.gemspec (mirroring default_gems_list.yml) and
# bundled gems come from gems/bundled_gems. This avoids reading NEWS.md as
# the source of "current versions", which would create a circular dependency
# with update-NEWS-gemlist.rb.
def load_current_versions
  require "rubygems"
  root = File.expand_path("..", __dir__)
  map = {}

  rg_path = File.join(root, "lib", "rubygems.rb")
  if File.exist?(rg_path)
    File.foreach(rg_path) do |line|
      if /^\s*VERSION\s*=\s*"([^"]+)"/ =~ line
        map["RubyGems"] = $1
        break
      end
    end
  end

  Dir.glob(File.join(root, "{ext,lib}/**/*.gemspec")).each do |path|
    spec = Gem::Specification.load(path)
    next unless spec
    map[spec.name] = spec.version.to_s
  end

  bundled_path = File.join(root, "gems", "bundled_gems")
  if File.exist?(bundled_path)
    File.foreach(bundled_path) do |line|
      next if line.start_with?("#")
      name, version = line.split(" ", 3)
      map[name] = version if name && version
    end
  end

  map
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
  when "RubyGems"
    { repo: "rubygems", org: "rubygems" }
  when "bundler"
    { repo: "rubygems", org: "rubygems", tag_prefix: "bundler-" }
  else
    { repo: name, org: "ruby" }
  end
end

def fetch_release_range(name, from_version, to_version, org, repo, tag_prefix: "")
  releases = []
  begin
    Octokit.releases("#{org}/#{repo}").each do |release|
      releases << release.tag_name
    end
  rescue Octokit::Error, Faraday::Error => e
    warn "warning: skipping #{name} (#{org}/#{repo}): #{e.class}: #{e.message}"
    return nil
  end

  # Keep only this gem's version-like tags and sort ascending by semantic version
  prefix = Regexp.escape(tag_prefix)
  releases = releases.select { |t| t =~ /\A#{prefix}v?\d/ }
  releases = releases.sort_by { |t| Gem::Version.new(t.sub(/\A#{prefix}/, "").sub(/^v/, "").tr("_", ".")) }

  start_index = releases.index("#{tag_prefix}v#{from_version}") || releases.index("#{tag_prefix}#{from_version}")
  end_index = releases.index("#{tag_prefix}v#{to_version}") || releases.index("#{tag_prefix}#{to_version}")

  # If the "to" version is unreleased (e.g. 4.1.0.dev), include every released
  # tag after the baseline up to the latest one available.
  end_index ||= releases.length - 1 if to_version =~ /(?:\.|-)(?:dev|beta|alpha|rc|pre)/i

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

    info = resolve_repo(name)
    org = info[:org]
    repo = info[:repo]
    tag_prefix = info[:tag_prefix] || ""

    release_range = fetch_release_range(name, versions_from[name], version, org, repo, tag_prefix: tag_prefix)
    next unless release_range

    footnote_links = release_range.map do |rel|
      tag = rel.sub(/\A#{Regexp.escape(tag_prefix)}/, "")
      {
        ref: "#{name}-#{tag}",
        url: "https://github.com/#{org}/#{repo}/releases/tag/#{rel}",
      }
    end

    results << {
      name: name,
      version: version,
      from_version: versions_from[name],
      release_range: release_range,
      footnote_links: footnote_links,
      tag_prefix: tag_prefix,
    }
  end

  results
end

def format_release_diff(result)
  prefix = Regexp.escape(result[:tag_prefix] || "")
  links = result[:release_range].map do |rel|
    tag = rel.sub(/\A#{prefix}/, "")
    "[#{tag}][#{result[:name]}-#{tag}]"
  end
  "  * #{result[:from_version]} to #{links.join(', ')}"
end

def print_results(results)
  footnote_lines = []

  results.each do |r|
    puts "* #{r[:name]} #{r[:version]}"
    puts format_release_diff(r)
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

  result_by_name = results.to_h { |r| [r[:name], r] }

  new_lines = []
  i = 0
  while i < lines.length
    line = lines[i]

    if line =~ /^\* ([A-Za-z0-9_\-]+)\s+(\d+(?:\.\d+){0,3})\b/
      gem_name = $1

      new_lines << line

      if (r = result_by_name[gem_name])
        # Skip any existing sub-bullet lines that follow
        while i + 1 < lines.length && lines[i + 1] =~ /^\s+\*/
          i += 1
        end

        new_lines << "#{format_release_diff(r)}\n"
      end
    else
      new_lines << line
    end
    i += 1
  end

  # All footnote definitions we can emit, indexed by ref name. Seed from existing
  # release-tag defs in the file so gems skipped this run (e.g. transient API
  # failures) keep their URLs, then overlay freshly fetched URLs.
  release_ref_pattern = %r{^\[([^\]]+)\]:\s+(https://github\.com/[^/]+/[^/]+/releases/tag/.*)}
  available_footnotes = {}
  new_lines.each do |line|
    if (m = line.match(release_ref_pattern))
      available_footnotes[m[1]] = "[#{m[1]}]: #{m[2]}"
    end
  end
  results.each do |r|
    r[:footnote_links].each do |fl|
      available_footnotes[fl[:ref]] = "[#{fl[:ref]}]: #{fl[:url]}"
    end
  end

  # Refs the regenerated body actually uses (e.g. `][gem-vX.Y.Z]`)
  used_refs = new_lines.join.scan(/\]\[([^\]]+)\]/).flatten.uniq

  # Drop all existing GitHub release-tag link defs; the used subset is
  # re-emitted below in body-ref order so the footer is deterministic.
  new_lines.reject! { |line| line.match?(release_ref_pattern) }

  # Trim trailing blank lines so the appended footer block is clean
  new_lines.pop while new_lines.last == "\n"
  new_lines << "\n" unless new_lines.last&.end_with?("\n")

  # Append footnote defs only for refs the body still references
  emitted = 0
  used_refs.each do |ref|
    if (footnote = available_footnotes[ref])
      new_lines << "#{footnote}\n"
      emitted += 1
    end
  end

  File.write(news_path, new_lines.join)
  puts "Updated #{news_path} with #{results.length} gem update entries and #{emitted} footnote links."
end

# --- Main ---

update_mode = ARGV.delete("--update")

versions_from = load_versions(ARGV[0])
versions_to = load_current_versions

results = collect_gem_updates(versions_from, versions_to)

print_results(results)

if update_mode
  update_news_md(results)
end
