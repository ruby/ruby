#!/usr/bin/env ruby
# Sync upstream github repositories to ruby repository.
# See `tool/sync_default_gems.rb --help` for how to use this.

require 'fileutils'
require "rbconfig"
require "find"
require "tempfile"

module SyncDefaultGems
  include FileUtils
  extend FileUtils

  module_function

  # upstream: "owner/repo"
  # branch: "branch_name"
  # mappings: [ ["path_in_upstream", "path_in_ruby"], ... ]
  #   NOTE: path_in_ruby is assumed to be "owned" by this gem, and the contents
  #   will be removed before sync
  # exclude: [ "fnmatch_pattern_after_mapping", ... ]
  Repository = Data.define(:upstream, :branch, :mappings, :exclude) do
    def excluded?(newpath)
      p = newpath
      until p == "."
        return true if exclude.any? {|pat| File.fnmatch?(pat, p, File::FNM_PATHNAME|File::FNM_EXTGLOB)}
        p = File.dirname(p)
      end
      false
    end

    def rewrite_for_ruby(path)
      newpath = mappings.find do |src, dst|
        if path == src || path.start_with?(src + "/")
          break path.sub(src, dst)
        end
      end
      return nil unless newpath
      return nil if excluded?(newpath)
      newpath
    end
  end

  CLASSICAL_DEFAULT_BRANCH = "master"

  def repo((upstream, branch), mappings, exclude: [])
    branch ||= CLASSICAL_DEFAULT_BRANCH
    exclude += ["ext/**/depend"]
    Repository.new(upstream:, branch:, mappings:, exclude:)
  end

  def lib((upstream, branch), gemspec_in_subdir: false)
    _org, name = upstream.split("/")
    gemspec_dst = gemspec_in_subdir ? "lib/#{name}/#{name}.gemspec" : "lib/#{name}.gemspec"
    repo([upstream, branch], [
      ["lib/#{name}.rb", "lib/#{name}.rb"],
      ["lib/#{name}", "lib/#{name}"],
      ["test/test_#{name}.rb", "test/test_#{name}.rb"],
      ["test/#{name}", "test/#{name}"],
      ["#{name}.gemspec", gemspec_dst],
    ])
  end

  # Note: tool/auto_review_pr.rb also depends on these constants.
  NO_UPSTREAM = [
    "lib/unicode_normalize",    # not to match with "lib/un"
  ]
  REPOSITORIES = {
    "io-console": repo("ruby/io-console", [
      ["ext/io/console", "ext/io/console"],
      ["test/io/console", "test/io/console"],
      ["lib/io/console", "ext/io/console/lib/console"],
      ["io-console.gemspec", "ext/io/console/io-console.gemspec"],
    ]),
    "io-nonblock": repo("ruby/io-nonblock", [
      ["ext/io/nonblock", "ext/io/nonblock"],
      ["test/io/nonblock", "test/io/nonblock"],
      ["io-nonblock.gemspec", "ext/io/nonblock/io-nonblock.gemspec"],
    ]),
    "io-wait": repo("ruby/io-wait", [
      ["ext/io/wait", "ext/io/wait"],
      ["test/io/wait", "test/io/wait"],
      ["io-wait.gemspec", "ext/io/wait/io-wait.gemspec"],
    ]),
    "net-http": repo("ruby/net-http", [
      ["lib/net/http.rb", "lib/net/http.rb"],
      ["lib/net/http", "lib/net/http"],
      ["test/net/http", "test/net/http"],
      ["net-http.gemspec", "lib/net/http/net-http.gemspec"],
    ]),
    "net-protocol": repo("ruby/net-protocol", [
      ["lib/net/protocol.rb", "lib/net/protocol.rb"],
      ["test/net/protocol", "test/net/protocol"],
      ["net-protocol.gemspec", "lib/net/net-protocol.gemspec"],
    ]),
    "open-uri": lib("ruby/open-uri"),
    "win32-registry": repo("ruby/win32-registry", [
      ["lib/win32/registry.rb", "ext/win32/lib/win32/registry.rb"],
      ["test/win32/test_registry.rb", "test/win32/test_registry.rb"],
      ["win32-registry.gemspec", "ext/win32/win32-registry.gemspec"],
    ]),
    English: lib("ruby/English"),
    cgi: repo("ruby/cgi", [
      ["ext/cgi", "ext/cgi"],
      ["lib/cgi/escape.rb", "lib/cgi/escape.rb"],
      ["test/cgi/test_cgi_escape.rb", "test/cgi/test_cgi_escape.rb"],
      ["test/cgi/update_env.rb", "test/cgi/update_env.rb"],
    ]),
    date: repo("ruby/date", [
      ["doc/date", "doc/date"],
      ["ext/date", "ext/date"],
      ["lib", "ext/date/lib"],
      ["test/date", "test/date"],
      ["date.gemspec", "ext/date/date.gemspec"],
    ], exclude: [
      "ext/date/lib/date_core.bundle",
    ]),
    delegate: lib("ruby/delegate"),
    did_you_mean: repo("ruby/did_you_mean", [
      ["lib/did_you_mean.rb", "lib/did_you_mean.rb"],
      ["lib/did_you_mean", "lib/did_you_mean"],
      ["test", "test/did_you_mean"],
      ["did_you_mean.gemspec", "lib/did_you_mean/did_you_mean.gemspec"],
    ], exclude: [
      "test/did_you_mean/lib",
      "test/did_you_mean/tree_spell/test_explore.rb",
    ]),
    digest: repo("ruby/digest", [
      ["ext/digest/lib/digest/sha2", "ext/digest/sha2/lib/sha2"],
      ["ext/digest", "ext/digest"],
      ["lib/digest.rb", "ext/digest/lib/digest.rb"],
      ["lib/digest/version.rb", "ext/digest/lib/digest/version.rb"],
      ["lib/digest/sha2.rb", "ext/digest/sha2/lib/sha2.rb"],
      ["test/digest", "test/digest"],
      ["digest.gemspec", "ext/digest/digest.gemspec"],
    ]),
    erb: repo("ruby/erb", [
      ["ext/erb", "ext/erb"],
      ["lib/erb", "lib/erb"],
      ["lib/erb.rb", "lib/erb.rb"],
      ["test/erb", "test/erb"],
      ["erb.gemspec", "lib/erb/erb.gemspec"],
      ["libexec/erb", "libexec/erb"],
    ]),
    error_highlight: repo("ruby/error_highlight", [
      ["lib/error_highlight.rb", "lib/error_highlight.rb"],
      ["lib/error_highlight", "lib/error_highlight"],
      ["test", "test/error_highlight"],
      ["error_highlight.gemspec", "lib/error_highlight/error_highlight.gemspec"],
    ]),
    etc: repo("ruby/etc", [
      ["ext/etc", "ext/etc"],
      ["test/etc", "test/etc"],
      ["etc.gemspec", "ext/etc/etc.gemspec"],
    ]),
    fcntl: repo("ruby/fcntl", [
      ["ext/fcntl", "ext/fcntl"],
      ["fcntl.gemspec", "ext/fcntl/fcntl.gemspec"],
    ]),
    fileutils: lib("ruby/fileutils"),
    find: lib("ruby/find"),
    forwardable: lib("ruby/forwardable", gemspec_in_subdir: true),
    ipaddr: lib("ruby/ipaddr"),
    json: repo("ruby/json", [
      ["ext/json/ext", "ext/json"],
      ["test/json", "test/json"],
      ["lib", "ext/json/lib"],
      ["json.gemspec", "ext/json/json.gemspec"],
    ], exclude: [
      "ext/json/lib/json/ext/.keep",
      "ext/json/lib/json/pure.rb",
      "ext/json/lib/json/pure",
      "ext/json/lib/json/truffle_ruby",
      "test/json/lib",
      "ext/json/extconf.rb",
    ]),
    mmtk: repo(["ruby/mmtk", "main"], [
      ["gc/mmtk", "gc/mmtk"],
    ]),
    open3: lib("ruby/open3", gemspec_in_subdir: true).tap {
      it.exclude << "lib/open3/jruby_windows.rb"
    },
    openssl: repo("ruby/openssl", [
      ["ext/openssl", "ext/openssl"],
      ["lib", "ext/openssl/lib"],
      ["test/openssl", "test/openssl"],
      ["sample", "sample/openssl"],
      ["openssl.gemspec", "ext/openssl/openssl.gemspec"],
      ["History.md", "ext/openssl/History.md"],
    ], exclude: [
      "test/openssl/envutil.rb",
      "ext/openssl/depend",
    ]),
    optparse: lib("ruby/optparse", gemspec_in_subdir: true).tap {
      it.mappings << ["doc/optparse", "doc/optparse"]
    },
    pathname: repo("ruby/pathname", [
      ["ext/pathname/pathname.c", "pathname.c"],
      ["lib/pathname_builtin.rb", "pathname_builtin.rb"],
      ["lib/pathname.rb", "lib/pathname.rb"],
      ["test/pathname", "test/pathname"],
    ]),
    pp: lib("ruby/pp"),
    prettyprint: lib("ruby/prettyprint"),
    prism: repo(["ruby/prism", "main"], [
      ["ext/prism", "prism"],
      ["lib/prism.rb", "lib/prism.rb"],
      ["lib/prism", "lib/prism"],
      ["test/prism", "test/prism"],
      ["src", "prism"],
      ["prism.gemspec", "lib/prism/prism.gemspec"],
      ["include/prism", "prism"],
      ["include/prism.h", "prism/prism.h"],
      ["config.yml", "prism/config.yml"],
      ["templates", "prism/templates"],
    ], exclude: [
      "prism/templates/{javascript,java,rbi,sig}",
      "test/prism/snapshots_test.rb",
      "test/prism/snapshots",
      "prism/extconf.rb",
      "prism/srcs.mk*",
    ]),
    psych: repo("ruby/psych", [
      ["ext/psych", "ext/psych"],
      ["lib", "ext/psych/lib"],
      ["test/psych", "test/psych"],
      ["psych.gemspec", "ext/psych/psych.gemspec"],
    ], exclude: [
      "ext/psych/lib/org",
      "ext/psych/lib/psych.jar",
      "ext/psych/lib/psych_jars.rb",
      "ext/psych/lib/psych.{bundle,so}",
      "ext/psych/lib/2.*",
      "ext/psych/yaml/LICENSE",
      "ext/psych/.gitignore",
    ]),
    resolv: repo("ruby/resolv", [
      ["lib/resolv.rb", "lib/resolv.rb"],
      ["test/resolv", "test/resolv"],
      ["resolv.gemspec", "lib/resolv.gemspec"],
      ["ext/win32/resolv/lib/resolv.rb", "ext/win32/lib/win32/resolv.rb"],
      ["ext/win32/resolv", "ext/win32/resolv"],
    ]),
    rubygems: repo("ruby/rubygems", [
      ["lib/rubygems.rb", "lib/rubygems.rb"],
      ["lib/rubygems", "lib/rubygems"],
      ["test/rubygems", "test/rubygems"],
      ["bundler/lib/bundler.rb", "lib/bundler.rb"],
      ["bundler/lib/bundler", "lib/bundler"],
      ["bundler/exe/bundle", "libexec/bundle"],
      ["bundler/exe/bundler", "libexec/bundler"],
      ["bundler/bundler.gemspec", "lib/bundler/bundler.gemspec"],
      ["bundler/spec", "spec/bundler"],
      *["bundle", "parallel_rspec", "rspec"].map {|binstub|
        ["bundler/bin/#{binstub}", "spec/bin/#{binstub}"]
      },
      *%w[dev_gems test_gems rubocop_gems standard_gems].flat_map {|gemfile|
        ["rb.lock", "rb"].map do |ext|
          ["tool/bundler/#{gemfile}.#{ext}", "tool/bundler/#{gemfile}.#{ext}"]
        end
      },
    ], exclude: [
      "spec/bundler/bin",
      "spec/bundler/support/artifice/vcr_cassettes",
      "spec/bundler/support/artifice/used_cassettes.txt",
      "lib/{bundler,rubygems}/**/{COPYING,LICENSE,README}{,.{md,txt,rdoc}}",
    ]),
    securerandom: lib("ruby/securerandom"),
    shellwords: lib("ruby/shellwords"),
    singleton: lib("ruby/singleton"),
    stringio: repo("ruby/stringio", [
      ["ext/stringio", "ext/stringio"],
      ["test/stringio", "test/stringio"],
      ["stringio.gemspec", "ext/stringio/stringio.gemspec"],
      ["doc/stringio", "doc/stringio"],
    ], exclude: [
      "ext/stringio/README.md",
    ]),
    strscan: repo("ruby/strscan", [
      ["ext/strscan", "ext/strscan"],
      ["lib", "ext/strscan/lib"],
      ["test/strscan", "test/strscan"],
      ["strscan.gemspec", "ext/strscan/strscan.gemspec"],
      ["doc/strscan", "doc/strscan"],
    ], exclude: [
      "ext/strscan/regenc.h",
      "ext/strscan/regint.h",
    ]),
    syntax_suggest: lib(["ruby/syntax_suggest", "main"], gemspec_in_subdir: true),
    tempfile: lib("ruby/tempfile"),
    time: lib("ruby/time"),
    timeout: lib("ruby/timeout"),
    tmpdir: lib("ruby/tmpdir"),
    tsort: lib("ruby/tsort"),
    un: lib("ruby/un"),
    uri: lib("ruby/uri", gemspec_in_subdir: true),
    weakref: lib("ruby/weakref"),
    yaml: lib("ruby/yaml", gemspec_in_subdir: true),
    zlib: repo("ruby/zlib", [
      ["ext/zlib", "ext/zlib"],
      ["test/zlib", "test/zlib"],
      ["zlib.gemspec", "ext/zlib/zlib.gemspec"],
    ]),
  }.transform_keys(&:to_s)

  class << Repository
    def find_upstream(file)
      return if NO_UPSTREAM.any? {|dst| file.start_with?(dst) }
      REPOSITORIES.find do |repo_name, repository|
        if repository.mappings.any? {|_src, dst| file.start_with?(dst) }
          break repo_name
        end
      end
    end

    def group(files)
      files.group_by {|file| find_upstream(file)}
    end
  end

  # Allow synchronizing commits up to this FETCH_DEPTH. We've historically merged PRs
  # with about 250 commits to ruby/ruby, so we use this depth for ruby/ruby in general.
  FETCH_DEPTH = 500

  def pipe_readlines(args, rs: "\0", chomp: true)
    IO.popen(args) do |f|
      f.readlines(rs, chomp: chomp)
    end
  end

  def porcelain_status(*pattern)
    pipe_readlines(%W"git status --porcelain --no-renames -z --" + pattern)
  end

  def replace_rdoc_ref(file)
    src = File.binread(file)
    changed = false
    changed |= src.gsub!(%r[\[\Khttps://docs\.ruby-lang\.org/en/master(?:/doc)?/(([A-Z]\w+(?:/[A-Z]\w+)*)|\w+_rdoc)\.html(\#\S+)?(?=\])]) do
      name, mod, label = $1, $2, $3
      mod &&= mod.gsub('/', '::')
      if label && (m = label.match(/\A\#(?:method-([ci])|(?:(?:class|module)-#{mod}-)?label)-([-+\w]+)\z/))
        scope, label = m[1], m[2]
        scope = scope ? scope.tr('ci', '.#') : '@'
      end
      "rdoc-ref:#{mod || name.chomp("_rdoc") + ".rdoc"}#{scope}#{label}"
    end
    changed or return false
    File.binwrite(file, src)
    return true
  end

  def replace_rdoc_ref_all
    result = porcelain_status("*.c", "*.rb", "*.rdoc")
    result.map! {|line| line[/\A.M (.*)/, 1]}
    result.compact!
    return if result.empty?
    result = pipe_readlines(%W"git grep -z -l -F [https://docs.ruby-lang.org/en/master/ --" + result)
    result.inject(false) {|changed, file| changed | replace_rdoc_ref(file)}
  end

  def replace_rdoc_ref_all_full
    Dir.glob("**/*.{c,rb,rdoc}").inject(false) {|changed, file| changed | replace_rdoc_ref(file)}
  end

  def rubygems_do_fixup
    gemspec_content = File.readlines("lib/bundler/bundler.gemspec").map do |line|
      next if line =~ /LICENSE\.md/

      line.gsub("bundler.gemspec", "lib/bundler/bundler.gemspec")
    end.compact.join
    File.write("lib/bundler/bundler.gemspec", gemspec_content)

    ["bundle", "parallel_rspec", "rspec"].each do |binstub|
      path = "spec/bin/#{binstub}"
      next unless File.exist?(path)
      content = File.read(path).gsub("../spec", "../bundler")
      File.write(path, content)
      chmod("+x", path)
    end
  end

  # We usually don't use this. Please consider using #sync_default_gems_with_commits instead.
  def sync_default_gems(gem)
    config = REPOSITORIES[gem]
    puts "Sync #{config.upstream}"

    upstream = File.join("..", "..", config.upstream)

    config.mappings.each do |src, dst|
      rm_rf(dst)
    end

    copied = Set.new
    config.mappings.each do |src, dst|
      prefix = File.join(upstream, src)
      # Maybe mapping needs to be updated?
      next unless File.exist?(prefix)
      Find.find(prefix) do |path|
        next if File.directory?(path)
        if copied.add?(path)
          newpath = config.rewrite_for_ruby(path.sub(%r{\A#{Regexp.escape(upstream)}/}, ""))
          next unless newpath
          mkdir_p(File.dirname(newpath))
          cp(path, newpath)
        end
      end
    end

    porcelain_status().each do |line|
      /\A(?:.)(?:.) (?<path>.*)\z/ =~ line or raise
      if config.excluded?(path)
        puts "Restoring excluded file: #{path}"
        IO.popen(%W"git checkout --" + [path], "rb", &:read)
      end
    end

    # RubyGems/Bundler needs special care
    if gem == "rubygems"
      rubygems_do_fixup
    end

    check_prerelease_version(gem)

    # Architecture-dependent files must not pollute libdir.
    rm_rf(Dir["lib/**/*.#{RbConfig::CONFIG['DLEXT']}"])
    replace_rdoc_ref_all
  end

  def check_prerelease_version(gem)
    return if ["rubygems", "mmtk", "cgi", "pathname"].include?(gem)

    require "net/https"
    require "json"
    require "uri"

    uri = URI("https://rubygems.org/api/v1/versions/#{gem.downcase}/latest.json")
    response = Net::HTTP.get(uri)
    latest_version = JSON.parse(response)["version"]

    gemspec = [
      "lib/#{gem}/#{gem}.gemspec",
      "lib/#{gem}.gemspec",
      "ext/#{gem}/#{gem}.gemspec",
      "ext/#{gem.split("-").join("/")}/#{gem}.gemspec",
      "lib/#{gem.split("-").first}/#{gem}.gemspec",
      "ext/#{gem.split("-").first}/#{gem}.gemspec",
      "lib/#{gem.split("-").join("/")}/#{gem}.gemspec",
    ].find{|gemspec| File.exist?(gemspec)}
    spec = Gem::Specification.load(gemspec)
    puts "#{gem}-#{spec.version} is not latest version of rubygems.org" if spec.version.to_s != latest_version
  end

  def message_filter(repo, sha, log, context: nil)
    unless repo.count("/") == 1 and /\A\S+\z/ =~ repo
      raise ArgumentError, "invalid repository: #{repo}"
    end
    unless /\A\h{10,40}\z/ =~ sha
      raise ArgumentError, "invalid commit-hash: #{sha}"
    end
    repo_url = "https://github.com/#{repo}"

    # Log messages generated by GitHub web UI have inconsistent line endings
    log = log.delete("\r")
    log << "\n" if !log.end_with?("\n")

    # Split the subject from the log message according to git conventions.
    # SPECIAL TREAT: when the first line ends with a dot `.` (which is not
    # obeying the conventions too), takes only that line.
    subject, log = log.split(/\A.+\.\K\n(?=\S)|\n(?:[ \t]*(?:\n|\z))/, 2)
    conv = proc do |s|
      mod = true if s.gsub!(/\b(?:(?i:fix(?:e[sd])?|close[sd]?|resolve[sd]?) +)\K#(?=\d+\b)|\bGH-#?(?=\d+\b)|\(\K#(?=\d+\))/) {
        "#{repo_url}/pull/"
      }
      mod |= true if s.gsub!(%r{(?<![-\[\](){}\w@/])(?:(\w+(?:-\w+)*/\w+(?:-\w+)*)@)?(\h{10,40})\b}) {|c|
        "https://github.com/#{$1 || repo}/commit/#{$2[0,12]}"
      }
      mod
    end
    subject = "[#{repo}] #{subject}"
    subject.gsub!(/\s*\n\s*/, " ")
    if conv[subject]
      if subject.size > 68
        subject.gsub!(/\G.{,67}[^\s.,][.,]*\K\s+/, "\n")
      end
    end
    commit_url = "#{repo_url}/commit/#{sha[0,10]}\n"
    sync_note = context ? "#{commit_url}\n#{context}" : commit_url
    if log and !log.empty?
      log.sub!(/(?<=\n)\n+\z/, '') # drop empty lines at the last
      conv[log]
      log.sub!(/(?:(\A\s*)|\s*\n)(?=((?i:^Co-authored-by:.*\n?)+)?\Z)/) {
        ($~.begin(1) ? "" : "\n\n") + sync_note + ($~.begin(2) ? "\n" : "")
      }
    else
      log = sync_note
    end
    "#{subject}\n\n#{log}"
  end

  def log_format(format, args, &block)
    IO.popen(%W[git -c core.autocrlf=false -c core.eol=lf
      log --no-show-signature --format=#{format}] + args, "rb", &block)
  end

  def commits_in_range(upto, exclude, toplevel:)
    args = [upto, *exclude.map {|s|"^#{s}"}]
    log_format('%H,%P,%s', %W"--first-parent" + args) do |f|
      f.read.split("\n").reverse.flat_map {|commit|
        hash, parents, subject = commit.split(',', 3)
        parents = parents.split

        # Non-merge commit
        if parents.size <= 1
          puts "#{hash} #{subject}"
          next [[hash, subject]]
        end

        # Clean 2-parent merge commit: follow the other parent as long as it
        # contains no potentially-non-clean merges
        if parents.size == 2 &&
            IO.popen(%W"git diff-tree --remerge-diff #{hash}", "rb", &:read).empty?
          puts "\e[2mChecking the other parent of #{hash} #{subject}\e[0m"
          ret = catch(:quit) {
            commits_in_range(parents[1], exclude + [parents[0]], toplevel: false)
          }
          next ret if ret
        end

        unless toplevel
          puts "\e[1mMerge commit with possible conflict resolution #{hash} #{subject}\e[0m"
          throw :quit
        end

        puts "#{hash} #{subject} " \
          "\e[1m[merge commit with possible conflicts, will do a squash merge]\e[0m"
        [[hash, subject]]
      }
    end
  end

  # Returns commit list as array of [commit_hash, subject, sync_note].
  def commits_in_ranges(ranges)
    ranges.flat_map do |range|
      exclude, upto = range.include?("..") ? range.split("..", 2) : ["#{range}~1", range]
      puts "Looking for commits in range #{exclude}..#{upto}"
      commits_in_range(upto, exclude.empty? ? [] : [exclude], toplevel: true)
    end.uniq
  end

  #--
  # Following methods used by sync_default_gems_with_commits return
  # true:  success
  # false: skipped
  # nil:   failed
  #++

  def resolve_conflicts(gem, sha, edit)
    # Discover unmerged files: any unstaged changes
    changes = porcelain_status()
    conflict = changes.grep(/\A(?:.[^ ?]) /) {$'}
    # If -e option is given, open each conflicted file with an editor
    unless conflict.empty?
      if edit
        case
        when (editor = ENV["GIT_EDITOR"] and !editor.empty?)
        when (editor = `git config core.editor` and (editor.chomp!; !editor.empty?))
        end
        if editor
          system([editor, conflict].join(' '))
          conflict.delete_if {|f| !File.exist?(f)}
          return true if conflict.empty?
          return system(*%w"git add --", *conflict)
        end
      end
      return false
    end

    return true
  end

  def collect_cacheinfo(tree)
    pipe_readlines(%W"git ls-tree -r -t -z #{tree}").filter_map do |line|
      fields, path = line.split("\t", 2)
      mode, type, object = fields.split(" ", 3)
      next unless type == "blob"
      [mode, type, object, path]
    end
  end

  def rewrite_cacheinfo(gem, blobs)
    config = REPOSITORIES[gem]
    rewritten = []
    ignored = blobs.dup
    ignored.delete_if do |mode, type, object, path|
      newpath = config.rewrite_for_ruby(path)
      next unless newpath
      rewritten << [mode, type, object, newpath]
    end
    [rewritten, ignored]
  end

  def make_commit_info(gem, sha)
    config = REPOSITORIES[gem]
    headers, orig = IO.popen(%W[git cat-file commit #{sha}], "rb", &:read).split("\n\n", 2)
    /^author (?<author_name>.+?) <(?<author_email>.*?)> (?<author_date>.+?)$/ =~ headers or
      raise "unable to parse author info for commit #{sha}"
    author = {
      "GIT_AUTHOR_NAME" => author_name,
      "GIT_AUTHOR_EMAIL" => author_email,
      "GIT_AUTHOR_DATE" => author_date,
    }
    context = nil
    if /^parent (?<first_parent>.{40})\nparent .{40}$/ =~ headers
      # Squashing a merge commit: keep authorship information
      context = IO.popen(%W"git shortlog #{first_parent}..#{sha} --", "rb", &:read)
    end
    message = message_filter(config.upstream, sha, orig, context: context)
    [author, message]
  end

  def fixup_commit(gem, commit)
    wt = File.join("tmp", "sync_default_gems-fixup-worktree")
    if File.directory?(wt)
      IO.popen(%W"git -C #{wt} clean -xdf", "rb", &:read)
      IO.popen(%W"git -C #{wt} reset --hard #{commit}", "rb", &:read)
    else
      IO.popen(%W"git worktree remove --force #{wt}", "rb", err: File::NULL, &:read)
      IO.popen(%W"git worktree add --detach #{wt} #{commit}", "rb", &:read)
    end
    raise "git worktree prepare failed for commit #{commit}" unless $?.success?

    Dir.chdir(wt) do
      if gem == "rubygems"
        rubygems_do_fixup
      end
      replace_rdoc_ref_all_full
    end

    IO.popen(%W"git -C #{wt} add -u", "rb", &:read)
    IO.popen(%W"git -C #{wt} commit --amend --no-edit", "rb", &:read)
    IO.popen(%W"git -C #{wt} rev-parse HEAD", "rb", &:read).chomp
  end

  def make_and_fixup_commit(gem, original_commit, cacheinfo, parent: nil, message: nil, author: nil)
    tree = Tempfile.create("sync_default_gems-#{gem}-index") do |f|
      File.unlink(f.path)
      IO.popen({"GIT_INDEX_FILE" => f.path},
               %W"git update-index --index-info", "wb", out: IO::NULL) do |io|
        cacheinfo.each do |mode, type, object, path|
          io.puts("#{mode} #{type} #{object}\t#{path}")
        end
      end
      raise "git update-index failed" unless $?.success?

      IO.popen({"GIT_INDEX_FILE" => f.path}, %W"git write-tree --missing-ok", "rb", &:read).chomp
    end

    args = ["-m", message || "Rewriten commit for #{original_commit}"]
    args += ["-p", parent] if parent
    commit = IO.popen({**author}, %W"git commit-tree #{tree}" + args, "rb", &:read).chomp

    # Apply changes that require a working tree
    commit = fixup_commit(gem, commit)

    commit
  end

  def rewrite_commit(gem, sha)
    author, message = make_commit_info(gem, sha)
    new_blobs = collect_cacheinfo("#{sha}")
    new_rewritten, new_ignored = rewrite_cacheinfo(gem, new_blobs)

    headers, _ = IO.popen(%W[git cat-file commit #{sha}], "rb", &:read).split("\n\n", 2)
    first_parent = headers[/^parent (.{40})$/, 1]
    unless first_parent
      # Root commit, first time to sync this repo
      return make_and_fixup_commit(gem, sha, new_rewritten, message: message, author: author)
    end

    old_blobs = collect_cacheinfo(first_parent)
    old_rewritten, old_ignored = rewrite_cacheinfo(gem, old_blobs)
    if old_ignored != new_ignored
      paths = (old_ignored + new_ignored - (old_ignored & new_ignored))
        .map {|*_, path| path}.uniq
      puts "\e\[1mIgnoring file changes not in mappings: #{paths.join(" ")}\e\[0m"
    end
    changed_paths = (old_rewritten + new_rewritten - (old_rewritten & new_rewritten))
      .map {|*_, path| path}.uniq
    if changed_paths.empty?
      puts "Skip commit only for tools or toplevel"
      return false
    end

    # Build commit objects from "cacheinfo"
    new_parent = make_and_fixup_commit(gem, first_parent, old_rewritten)
    new_commit = make_and_fixup_commit(gem, sha, new_rewritten, parent: new_parent, message: message, author: author)
    puts "Created a temporary commit for cherry-pick: #{new_commit}"
    new_commit
  end

  def pickup_commit(gem, sha, edit)
    rewritten = rewrite_commit(gem, sha)

    # No changes remaining after rewriting
    return false unless rewritten

    # Attempt to cherry-pick a commit
    result = IO.popen(%W"git cherry-pick #{rewritten}", "rb", err: [:child, :out], &:read)
    unless $?.success?
      if result =~ /The previous cherry-pick is now empty/
        system(*%w"git cherry-pick --skip")
        puts "Skip empty commit #{sha}"
        return false
      end

      # If the cherry-pick attempt failed, try to resolve conflicts.
      # Skip the commit, if it contains unresolved conflicts or no files to pick up.
      unless resolve_conflicts(gem, sha, edit)
        system(*%w"git --no-pager diff") if !edit # If failed, show `git diff` unless editing
        `git reset` && `git checkout .` && `git clean -fd` # Clean up un-committed diffs
        return nil # Fail unless cherry-picked
      end

      # Commit cherry-picked commit
      if porcelain_status().empty?
        system(*%w"git cherry-pick --skip")
        return false
      else
        system(*%w"git cherry-pick --continue --no-edit")
        return nil unless $?.success?
      end
    end

    new_head = IO.popen(%W"git rev-parse HEAD", "rb", &:read).chomp
    puts "Committed cherry-pick as #{new_head}"
    return true
  end

  # @param gem [String] A gem name, also used as a git remote name. REPOSITORIES converts it to the appropriate GitHub repository.
  # @param ranges [Array<String>, true] "commit", "before..after", or true. Note that it will NOT sync "before" (but commits after that).
  # @param edit [TrueClass] Set true if you want to resolve conflicts. Obviously, update-default-gem.sh doesn't use this.
  def sync_default_gems_with_commits(gem, ranges, edit: nil)
    config = REPOSITORIES[gem]
    repo, default_branch = config.upstream, config.branch
    puts "Sync #{repo} with commit history."

    # Fetch the repository to be synchronized
    IO.popen(%W"git remote") do |f|
      unless f.read.split.include?(gem)
        `git remote add #{gem} https://github.com/#{repo}.git`
      end
    end
    system(*%W"git fetch --no-tags --depth=#{FETCH_DEPTH} #{gem} #{default_branch}")

    # If -a is given, discover all commits since the last picked commit
    if ranges == true
      pattern = "https://github\.com/#{Regexp.quote(repo)}/commit/([0-9a-f]+)$"
      log = log_format('%B', %W"-E --grep=#{pattern} -n1 --", &:read)
      ranges = ["#{log[%r[#{pattern}\n\s*(?i:co-authored-by:.*)*\s*\Z], 1]}..#{gem}/#{default_branch}"]
    end
    commits = commits_in_ranges(ranges)
    if commits.empty?
      puts "No commits to pick"
      return true
    end

    failed_commits = []
    commits.each do |sha, subject|
      puts "----"
      puts "Pick #{sha} #{subject}"
      case pickup_commit(gem, sha, edit)
      when false
        # skipped
      when nil
        failed_commits << [sha, subject]
      end
    end

    unless failed_commits.empty?
      puts "---- failed commits ----"
      failed_commits.each do |sha, subject|
        puts "#{sha} #{subject}"
      end
      return false
    end
    return true
  end

  def sync_lib(repo, upstream = nil)
    unless upstream and File.directory?(upstream) or File.directory?(upstream = "../#{repo}")
      abort %[Expected '#{upstream}' \(#{File.expand_path("#{upstream}")}\) to be a directory, but it wasn't.]
    end
    rm_rf(["lib/#{repo}.rb", "lib/#{repo}/*", "test/test_#{repo}.rb"])
    cp_r(Dir.glob("#{upstream}/lib/*"), "lib")
    tests = if File.directory?("test/#{repo}")
              "test/#{repo}"
            else
              "test/test_#{repo}.rb"
            end
    cp_r("#{upstream}/#{tests}", "test") if File.exist?("#{upstream}/#{tests}")
    gemspec = if File.directory?("lib/#{repo}")
                "lib/#{repo}/#{repo}.gemspec"
              else
                "lib/#{repo}.gemspec"
              end
    cp_r("#{upstream}/#{repo}.gemspec", "#{gemspec}")
  end

  def update_default_gems(gem, release: false)
    config = REPOSITORIES[gem]
    author, repository = config.upstream.split('/')
    default_branch = config.branch

    puts "Update #{author}/#{repository}"

    unless File.exist?("../../#{author}/#{repository}")
      mkdir_p("../../#{author}")
      `git clone git@github.com:#{author}/#{repository}.git ../../#{author}/#{repository}`
    end

    Dir.chdir("../../#{author}/#{repository}") do
      unless `git remote`.match(/ruby\-core/)
        `git remote add ruby-core git@github.com:ruby/ruby.git`
      end
      `git fetch ruby-core master --no-tags`
      unless `git branch`.match(/ruby\-core/)
        `git checkout ruby-core/master`
        `git branch ruby-core`
      end
      `git checkout ruby-core`
      `git rebase ruby-core/master`
      `git fetch origin --tags`

      if release
        last_release = `git tag | sort -V`.chomp.split.delete_if{|v| v =~ /pre|beta/ }.last
        `git checkout #{last_release}`
      else
        `git checkout #{default_branch}`
        `git rebase origin/#{default_branch}`
      end
    end
  end

  case ARGV[0]
  when "up"
    if ARGV[1]
      update_default_gems(ARGV[1])
    else
      REPOSITORIES.each_key {|gem| update_default_gems(gem)}
    end
  when "all"
    if ARGV[1] == "release"
      REPOSITORIES.each_key do |gem|
        update_default_gems(gem, release: true)
        sync_default_gems(gem)
      end
    else
      REPOSITORIES.each_key {|gem| sync_default_gems(gem)}
    end
  when "list"
    ARGV.shift
    pattern = Regexp.new(ARGV.join('|'))
    REPOSITORIES.each do |gem, config|
      next unless pattern =~ gem or pattern =~ config.upstream
      printf "%-15s https://github.com/%s\n", gem, config.upstream
    end
  when "rdoc-ref"
    ARGV.shift
    pattern = ARGV.empty? ? %w[*.c *.rb *.rdoc] : ARGV
    result = pipe_readlines(%W"git grep -z -l -F [https://docs.ruby-lang.org/en/master/ --" + pattern)
    result.inject(false) do |changed, file|
      if replace_rdoc_ref(file)
        puts "replaced rdoc-ref in #{file}"
        changed = true
      end
      changed
    end
  when nil, "-h", "--help"
    puts <<-HELP
\e[1mSync with upstream code of default libraries\e[0m

\e[1mImport all default gems through `git clone` and `cp -rf` (git commits are lost)\e[0m
  ruby #$0 all

\e[1mImport all released version of default gems\e[0m
  ruby #$0 all release

\e[1mImport a default gem with specific gem same as all command\e[0m
  ruby #$0 rubygems

\e[1mPick a single commit from the upstream repository\e[0m
  ruby #$0 rubygems 97e9768612

\e[1mPick a commit range from the upstream repository\e[0m
  ruby #$0 rubygems 97e9768612..9e53702832

\e[1mPick all commits since the last picked commit\e[0m
  ruby #$0 -a rubygems

\e[1mUpdate repositories of default gems\e[0m
  ruby #$0 up

\e[1mList known libraries\e[0m
  ruby #$0 list

\e[1mList known libraries matching with patterns\e[0m
  ruby #$0 list read
    HELP

    exit
  else
    while /\A-/ =~ ARGV[0]
      case ARGV[0]
      when "-e"
        edit = true
        ARGV.shift
      when "-a"
        auto = true
        ARGV.shift
      else
        $stderr.puts "Unknown command line option: #{ARGV[0]}"
        exit 1
      end
    end
    gem = ARGV.shift
    if ARGV[0]
      exit sync_default_gems_with_commits(gem, ARGV, edit: edit)
    elsif auto
      exit sync_default_gems_with_commits(gem, true, edit: edit)
    else
      sync_default_gems(gem)
    end
  end if $0 == __FILE__
end
