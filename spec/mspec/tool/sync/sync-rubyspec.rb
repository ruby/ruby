IMPLS = {
  truffleruby: {
    git: "https://github.com/graalvm/truffleruby.git",
    from_commit: "f10ab6988d",
  },
  jruby: {
    git: "https://github.com/jruby/jruby.git",
    from_commit: "f10ab6988d",
  },
  rbx: {
    git: "https://github.com/rubinius/rubinius.git",
  },
  mri: {
    git: "https://github.com/ruby/ruby.git",
    master: "trunk",
    prefix: "spec/rubyspec",
  },
}

# Assuming the rubyspec repo is a sibling of the mspec repo
RUBYSPEC_REPO = File.expand_path("../../../../rubyspec", __FILE__)
raise RUBYSPEC_REPO unless Dir.exist?(RUBYSPEC_REPO)

NOW = Time.now

class RubyImplementation
  attr_reader :name

  def initialize(name, data)
    @name = name.to_s
    @data = data
  end

  def git_url
    @data[:git]
  end

  def default_branch
    @data[:master] || "master"
  end

  def repo_name
    File.basename(git_url, ".git")
  end

  def repo_org
    File.basename(File.dirname(git_url))
  end

  def from_commit
    from = @data[:from_commit]
    "#{from}..." if from
  end

  def prefix
    @data[:prefix] || "spec/ruby"
  end

  def rebased_branch
    "#{@name}-rebased"
  end
end

def sh(*args)
  puts args.join(' ')
  system(*args)
  raise unless $?.success?
end

def branch?(name)
  branches = `git branch`.sub('*', '').lines.map(&:strip)
  branches.include?(name)
end

def update_repo(impl)
  unless File.directory? impl.repo_name
    sh "git", "clone", impl.git_url
  end

  Dir.chdir(impl.repo_name) do
    puts Dir.pwd

    sh "git", "checkout", impl.default_branch
    sh "git", "pull"
  end
end

def filter_commits(impl)
  Dir.chdir(impl.repo_name) do
    date = NOW.strftime("%F")
    branch = "specs-#{date}"

    unless branch?(branch)
      sh "git", "checkout", "-b", branch
      sh "git", "filter-branch", "-f", "--subdirectory-filter", impl.prefix, *impl.from_commit
      sh "git", "push", "-f", RUBYSPEC_REPO, "#{branch}:#{impl.name}"
    end
  end
end

def rebase_commits(impl)
  Dir.chdir(RUBYSPEC_REPO) do
    sh "git", "checkout", "master"
    sh "git", "pull"

    rebased = impl.rebased_branch
    if branch?(rebased)
      puts "#{rebased} already exists, assuming it correct"
      sh "git", "checkout", rebased
    else
      sh "git", "checkout", impl.name

      if ENV["LAST_MERGE"]
        last_merge = `git log -n 1 --format='%H %ct' #{ENV["LAST_MERGE"]}`
      else
        last_merge = `git log --grep='Merge ruby/spec commit' -n 1 --format='%H %ct'`
      end
      last_merge, commit_timestamp = last_merge.chomp.split(' ')

      raise "Could not find last merge" unless last_merge
      puts "Last merge is #{last_merge}"

      commit_date = Time.at(Integer(commit_timestamp))
      days_since_last_merge = (NOW-commit_date) / 86400
      if days_since_last_merge > 60
        raise "#{days_since_last_merge} since last merge, probably wrong commit"
      end

      puts "Rebasing..."
      sh "git", "branch", "-D", rebased if branch?(rebased)
      sh "git", "checkout", "-b", rebased, impl.name
      sh "git", "rebase", "--onto", "master", last_merge
    end
  end
end

def test_new_specs
  require "yaml"
  Dir.chdir(RUBYSPEC_REPO) do
    versions = YAML.load_file(".travis.yml")
    versions = versions["matrix"]["include"].map { |job| job["rvm"] }
    versions.delete "ruby-head"
    min_version, max_version = versions.minmax

    run_rubyspec = -> version {
      command = "chruby #{version} && ../mspec/bin/mspec -j"
      sh ENV["SHELL"], "-c", command
    }
    run_rubyspec[min_version]
    run_rubyspec[max_version]
    run_rubyspec["trunk"]
  end
end

def verify_commits(impl)
  puts
  Dir.chdir(RUBYSPEC_REPO) do
    history = `git log master...`
    history.lines.slice_before(/^commit \h{40}$/).each do |commit, *message|
      commit = commit.chomp.split.last
      message = message.join
      if /\W(#\d+)/ === message
        puts "Commit #{commit} contains an unqualified issue number: #{$1}"
        puts "Replace it with #{impl.repo_org}/#{impl.repo_name}#{$1}"
        sh "git", "rebase", "-i", "#{commit}^"
      end
    end

    puts "Manually check commit messages:"
    sh "git", "log", "master..."
  end
end

def fast_forward_master(impl)
  Dir.chdir(RUBYSPEC_REPO) do
    sh "git", "checkout", "master"
    sh "git", "merge", "--ff-only", "#{impl.name}-rebased"
  end
end

def check_ci
  puts
  puts <<-EOS
  Push to master, and check that the CI passes:
    https://github.com/ruby/spec/commits/master
  EOS
end

def main(impls)
  impls.each_pair do |impl, data|
    impl = RubyImplementation.new(impl, data)
    update_repo(impl)
    filter_commits(impl)
    rebase_commits(impl)
    test_new_specs
    verify_commits(impl)
    fast_forward_master(impl)
    check_ci
  end
end

if ARGV == ["all"]
  impls = IMPLS
else
  args = ARGV.map { |arg| arg.to_sym }
  raise ARGV.to_s unless (args - IMPLS.keys).empty?
  impls = IMPLS.select { |impl| args.include?(impl) }
end

main(impls)
