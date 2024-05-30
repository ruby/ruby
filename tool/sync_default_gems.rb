#!/usr/bin/env ruby
# Sync upstream github repositories to ruby repository.
# See `tool/sync_default_gems.rb --help` for how to use this.

require 'fileutils'
require "rbconfig"

module SyncDefaultGems
  include FileUtils
  extend FileUtils

  module_function

  REPOSITORIES = {
    "io-console": 'ruby/io-console',
    "io-nonblock": 'ruby/io-nonblock',
    "io-wait": 'ruby/io-wait',
    "net-http": "ruby/net-http",
    "net-protocol": "ruby/net-protocol",
    "open-uri": "ruby/open-uri",
    English: "ruby/English",
    benchmark: "ruby/benchmark",
    cgi: "ruby/cgi",
    date: 'ruby/date',
    delegate: "ruby/delegate",
    did_you_mean: "ruby/did_you_mean",
    digest: "ruby/digest",
    erb: "ruby/erb",
    error_highlight: "ruby/error_highlight",
    etc: 'ruby/etc',
    fcntl: 'ruby/fcntl',
    fiddle: 'ruby/fiddle',
    fileutils: 'ruby/fileutils',
    find: "ruby/find",
    forwardable: "ruby/forwardable",
    ipaddr: 'ruby/ipaddr',
    irb: 'ruby/irb',
    json: 'flori/json',
    logger: 'ruby/logger',
    open3: "ruby/open3",
    openssl: "ruby/openssl",
    optparse: "ruby/optparse",
    ostruct: 'ruby/ostruct',
    pathname: "ruby/pathname",
    pp: "ruby/pp",
    prettyprint: "ruby/prettyprint",
    prism: ["ruby/prism", "main"],
    pstore: "ruby/pstore",
    psych: 'ruby/psych',
    rdoc: 'ruby/rdoc',
    readline: "ruby/readline",
    reline: 'ruby/reline',
    resolv: "ruby/resolv",
    rubygems: 'rubygems/rubygems',
    securerandom: "ruby/securerandom",
    set: "ruby/set",
    shellwords: "ruby/shellwords",
    singleton: "ruby/singleton",
    stringio: 'ruby/stringio',
    strscan: 'ruby/strscan',
    syntax_suggest: ["ruby/syntax_suggest", "main"],
    tempfile: "ruby/tempfile",
    time: "ruby/time",
    timeout: "ruby/timeout",
    tmpdir: "ruby/tmpdir",
    tsort: "ruby/tsort",
    un: "ruby/un",
    uri: "ruby/uri",
    weakref: "ruby/weakref",
    win32ole: "ruby/win32ole",
    yaml: "ruby/yaml",
    zlib: 'ruby/zlib',
  }.transform_keys(&:to_s)

  CLASSICAL_DEFAULT_BRANCH = "master"

  class << REPOSITORIES
    def [](gem)
      repo, branch = super(gem)
      return repo, branch || CLASSICAL_DEFAULT_BRANCH
    end

    def each_pair
      super do |gem, (repo, branch)|
        yield gem, [repo, branch || CLASSICAL_DEFAULT_BRANCH]
      end
    end
  end

  def pipe_readlines(args, rs: "\0", chomp: true)
    IO.popen(args) do |f|
      f.readlines(rs, chomp: chomp)
    end
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
    result = pipe_readlines(%W"git status --porcelain -z -- *.c *.rb *.rdoc")
    result.map! {|line| line[/\A.M (.*)/, 1]}
    result.compact!
    return if result.empty?
    result = pipe_readlines(%W"git grep -z -l -F [https://docs.ruby-lang.org/en/master/ --" + result)
    result.inject(false) {|changed, file| changed | replace_rdoc_ref(file)}
  end

  # We usually don't use this. Please consider using #sync_default_gems_with_commits instead.
  def sync_default_gems(gem)
    repo, = REPOSITORIES[gem]
    puts "Sync #{repo}"

    upstream = File.join("..", "..", repo)

    case gem
    when "rubygems"
      rm_rf(%w[lib/rubygems lib/rubygems.rb test/rubygems])
      cp_r(Dir.glob("#{upstream}/lib/rubygems*"), "lib")
      cp_r("#{upstream}/test/rubygems", "test")
      rm_rf(%w[lib/bundler lib/bundler.rb libexec/bundler libexec/bundle spec/bundler tool/bundler/*])
      cp_r(Dir.glob("#{upstream}/bundler/lib/bundler*"), "lib")
      cp_r(Dir.glob("#{upstream}/bundler/exe/bundle*"), "libexec")

      gemspec_content = File.readlines("#{upstream}/bundler/bundler.gemspec").map do |line|
        next if line =~ /LICENSE\.md/

        line.gsub("bundler.gemspec", "lib/bundler/bundler.gemspec")
      end.compact.join
      File.write("lib/bundler/bundler.gemspec", gemspec_content)

      cp_r("#{upstream}/bundler/spec", "spec/bundler")
      %w[dev_gems test_gems rubocop_gems standard_gems].each do |gemfile|
        cp_r("#{upstream}/tool/bundler/#{gemfile}.rb", "tool/bundler")
      end
      rm_rf Dir.glob("spec/bundler/support/artifice/{vcr_cassettes,used_cassettes.txt}")
      rm_rf Dir.glob("lib/{bundler,rubygems}/**/{COPYING,LICENSE,README}{,.{md,txt,rdoc}}")
    when "rdoc"
      rm_rf(%w[lib/rdoc lib/rdoc.rb test/rdoc libexec/rdoc libexec/ri])
      cp_r(Dir.glob("#{upstream}/lib/rdoc*"), "lib")
      cp_r("#{upstream}/doc/rdoc", "doc")
      cp_r("#{upstream}/test/rdoc", "test")
      cp_r("#{upstream}/rdoc.gemspec", "lib/rdoc")
      cp_r("#{upstream}/Gemfile", "lib/rdoc")
      cp_r("#{upstream}/Rakefile", "lib/rdoc")
      cp_r("#{upstream}/exe/rdoc", "libexec")
      cp_r("#{upstream}/exe/ri", "libexec")
      parser_files = {
        'lib/rdoc/markdown.kpeg' => 'lib/rdoc/markdown.rb',
        'lib/rdoc/markdown/literals.kpeg' => 'lib/rdoc/markdown/literals.rb',
        'lib/rdoc/rd/block_parser.ry' => 'lib/rdoc/rd/block_parser.rb',
        'lib/rdoc/rd/inline_parser.ry' => 'lib/rdoc/rd/inline_parser.rb'
      }
      Dir.chdir(upstream) do
        `bundle install`
        parser_files.each_value do |dst|
          `bundle exec rake #{dst}`
        end
      end
      parser_files.each_pair do |src, dst|
        rm_rf(src)
        cp_r("#{upstream}/#{dst}", dst)
      end
      `git checkout lib/rdoc/.document`
      rm_rf(%w[lib/rdoc/Gemfile lib/rdoc/Rakefile])
    when "reline"
      rm_rf(%w[lib/reline lib/reline.rb test/reline])
      cp_r(Dir.glob("#{upstream}/lib/reline*"), "lib")
      cp_r("#{upstream}/test/reline", "test")
      cp_r("#{upstream}/reline.gemspec", "lib/reline")
    when "irb"
      rm_rf(%w[lib/irb lib/irb.rb test/irb])
      cp_r(Dir.glob("#{upstream}/lib/irb*"), "lib")
      cp_r("#{upstream}/test/irb", "test")
      cp_r("#{upstream}/irb.gemspec", "lib/irb")
      cp_r("#{upstream}/man/irb.1", "man/irb.1")
      cp_r("#{upstream}/doc/irb", "doc")
    when "json"
      rm_rf(%w[ext/json test/json])
      cp_r("#{upstream}/ext/json/ext", "ext/json")
      cp_r("#{upstream}/tests", "test/json")
      rm_rf("test/json/lib")
      cp_r("#{upstream}/lib", "ext/json")
      cp_r("#{upstream}/json.gemspec", "ext/json")
      rm_rf(%w[ext/json/lib/json/ext ext/json/lib/json/pure.rb ext/json/lib/json/pure])
      `git checkout ext/json/extconf.rb ext/json/parser/prereq.mk ext/json/generator/depend ext/json/parser/depend ext/json/depend`
    when "psych"
      rm_rf(%w[ext/psych test/psych])
      cp_r("#{upstream}/ext/psych", "ext")
      cp_r("#{upstream}/lib", "ext/psych")
      cp_r("#{upstream}/test/psych", "test")
      rm_rf(%w[ext/psych/lib/org ext/psych/lib/psych.jar ext/psych/lib/psych_jars.rb])
      rm_rf(%w[ext/psych/lib/psych.{bundle,so} ext/psych/lib/2.*])
      rm_rf(["ext/psych/yaml/LICENSE"])
      cp_r("#{upstream}/psych.gemspec", "ext/psych")
      `git checkout ext/psych/depend ext/psych/.gitignore`
    when "fiddle"
      rm_rf(%w[ext/fiddle test/fiddle])
      cp_r("#{upstream}/ext/fiddle", "ext")
      cp_r("#{upstream}/lib", "ext/fiddle")
      cp_r("#{upstream}/test/fiddle", "test")
      cp_r("#{upstream}/fiddle.gemspec", "ext/fiddle")
      `git checkout ext/fiddle/depend`
      rm_rf(%w[ext/fiddle/lib/fiddle.{bundle,so}])
    when "stringio"
      rm_rf(%w[ext/stringio test/stringio])
      cp_r("#{upstream}/ext/stringio", "ext")
      cp_r("#{upstream}/test/stringio", "test")
      cp_r("#{upstream}/stringio.gemspec", "ext/stringio")
      `git checkout ext/stringio/depend ext/stringio/README.md`
    when "io-console"
      rm_rf(%w[ext/io/console test/io/console])
      cp_r("#{upstream}/ext/io/console", "ext/io")
      cp_r("#{upstream}/test/io/console", "test/io")
      mkdir_p("ext/io/console/lib")
      cp_r("#{upstream}/lib/io/console", "ext/io/console/lib")
      rm_rf("ext/io/console/lib/console/ffi")
      cp_r("#{upstream}/io-console.gemspec", "ext/io/console")
      `git checkout ext/io/console/depend`
    when "io-nonblock"
      rm_rf(%w[ext/io/nonblock test/io/nonblock])
      cp_r("#{upstream}/ext/io/nonblock", "ext/io")
      cp_r("#{upstream}/test/io/nonblock", "test/io")
      cp_r("#{upstream}/io-nonblock.gemspec", "ext/io/nonblock")
      `git checkout ext/io/nonblock/depend`
    when "io-wait"
      rm_rf(%w[ext/io/wait test/io/wait])
      cp_r("#{upstream}/ext/io/wait", "ext/io")
      cp_r("#{upstream}/test/io/wait", "test/io")
      cp_r("#{upstream}/io-wait.gemspec", "ext/io/wait")
      `git checkout ext/io/wait/depend`
    when "etc"
      rm_rf(%w[ext/etc test/etc])
      cp_r("#{upstream}/ext/etc", "ext")
      cp_r("#{upstream}/test/etc", "test")
      cp_r("#{upstream}/etc.gemspec", "ext/etc")
      `git checkout ext/etc/depend`
    when "date"
      rm_rf(%w[ext/date test/date])
      cp_r("#{upstream}/doc/date", "doc")
      cp_r("#{upstream}/ext/date", "ext")
      cp_r("#{upstream}/lib", "ext/date")
      cp_r("#{upstream}/test/date", "test")
      cp_r("#{upstream}/date.gemspec", "ext/date")
      `git checkout ext/date/depend`
      rm_rf(["ext/date/lib/date_core.bundle"])
    when "zlib"
      rm_rf(%w[ext/zlib test/zlib])
      cp_r("#{upstream}/ext/zlib", "ext")
      cp_r("#{upstream}/test/zlib", "test")
      cp_r("#{upstream}/zlib.gemspec", "ext/zlib")
      `git checkout ext/zlib/depend`
    when "fcntl"
      rm_rf(%w[ext/fcntl])
      cp_r("#{upstream}/ext/fcntl", "ext")
      cp_r("#{upstream}/fcntl.gemspec", "ext/fcntl")
      `git checkout ext/fcntl/depend`
    when "strscan"
      rm_rf(%w[ext/strscan test/strscan])
      cp_r("#{upstream}/ext/strscan", "ext")
      cp_r("#{upstream}/test/strscan", "test")
      cp_r("#{upstream}/strscan.gemspec", "ext/strscan")
      mv(["ext/strscan/helper_methods.md", "ext/strscan/link_refs.txt", "ext/strscan/strscan.md"], "doc/strscan")
      rm_rf(%w["ext/strscan/regenc.h ext/strscan/regint.h"])
      `git checkout ext/strscan/depend`
    when "cgi"
      rm_rf(%w[lib/cgi.rb lib/cgi ext/cgi test/cgi])
      cp_r("#{upstream}/ext/cgi", "ext")
      cp_r("#{upstream}/lib", ".")
      rm_rf("lib/cgi/escape.jar")
      cp_r("#{upstream}/test/cgi", "test")
      cp_r("#{upstream}/cgi.gemspec", "lib/cgi")
      `git checkout ext/cgi/escape/depend`
    when "openssl"
      rm_rf(%w[ext/openssl test/openssl])
      cp_r("#{upstream}/ext/openssl", "ext")
      cp_r("#{upstream}/lib", "ext/openssl")
      cp_r("#{upstream}/test/openssl", "test")
      rm_rf("test/openssl/envutil.rb")
      cp_r("#{upstream}/openssl.gemspec", "ext/openssl")
      cp_r("#{upstream}/History.md", "ext/openssl")
      `git checkout ext/openssl/depend`
    when "net-protocol"
      rm_rf(%w[lib/net/protocol.rb lib/net/net-protocol.gemspec test/net/protocol])
      cp_r("#{upstream}/lib/net/protocol.rb", "lib/net")
      cp_r("#{upstream}/test/net/protocol", "test/net")
      cp_r("#{upstream}/net-protocol.gemspec", "lib/net")
    when "net-http"
      rm_rf(%w[lib/net/http.rb lib/net/http test/net/http])
      cp_r("#{upstream}/lib/net/http.rb", "lib/net")
      cp_r("#{upstream}/lib/net/http", "lib/net")
      cp_r("#{upstream}/test/net/http", "test/net")
      cp_r("#{upstream}/net-http.gemspec", "lib/net/http")
    when "did_you_mean"
      rm_rf(%w[lib/did_you_mean lib/did_you_mean.rb test/did_you_mean])
      cp_r(Dir.glob("#{upstream}/lib/did_you_mean*"), "lib")
      cp_r("#{upstream}/did_you_mean.gemspec", "lib/did_you_mean")
      cp_r("#{upstream}/test", "test/did_you_mean")
      rm_rf("test/did_you_mean/lib")
      rm_rf(%w[test/did_you_mean/tree_spell/test_explore.rb])
    when "erb"
      rm_rf(%w[lib/erb* test/erb libexec/erb])
      cp_r("#{upstream}/lib/erb.rb", "lib")
      cp_r("#{upstream}/test/erb", "test")
      cp_r("#{upstream}/erb.gemspec", "lib")
      cp_r("#{upstream}/libexec/erb", "libexec")
    when "pathname"
      rm_rf(%w[ext/pathname test/pathname])
      cp_r("#{upstream}/ext/pathname", "ext")
      cp_r("#{upstream}/test/pathname", "test")
      cp_r("#{upstream}/lib", "ext/pathname")
      cp_r("#{upstream}/pathname.gemspec", "ext/pathname")
      `git checkout ext/pathname/depend`
    when "digest"
      rm_rf(%w[ext/digest test/digest])
      cp_r("#{upstream}/ext/digest", "ext")
      mkdir_p("ext/digest/lib/digest")
      cp_r("#{upstream}/lib/digest.rb", "ext/digest/lib/")
      cp_r("#{upstream}/lib/digest/version.rb", "ext/digest/lib/digest/")
      mkdir_p("ext/digest/sha2/lib")
      cp_r("#{upstream}/lib/digest/sha2.rb", "ext/digest/sha2/lib")
      move("ext/digest/lib/digest/sha2", "ext/digest/sha2/lib")
      cp_r("#{upstream}/test/digest", "test")
      cp_r("#{upstream}/digest.gemspec", "ext/digest")
      `git checkout ext/digest/depend ext/digest/*/depend`
    when "set"
      sync_lib gem, upstream
      cp_r(Dir.glob("#{upstream}/test/*"), "test/set")
    when "optparse"
      sync_lib gem, upstream
      rm_rf(%w[doc/optparse])
      mkdir_p("doc/optparse")
      cp_r("#{upstream}/doc/optparse", "doc")
    when "error_highlight"
      rm_rf(%w[lib/error_highlight lib/error_highlight.rb test/error_highlight])
      cp_r(Dir.glob("#{upstream}/lib/error_highlight*"), "lib")
      cp_r("#{upstream}/error_highlight.gemspec", "lib/error_highlight")
      cp_r("#{upstream}/test", "test/error_highlight")
    when "win32ole"
      sync_lib gem, upstream
      rm_rf(%w[ext/win32ole/lib])
      Dir.mkdir(*%w[ext/win32ole/lib])
      move("lib/win32ole/win32ole.gemspec", "ext/win32ole")
      move(Dir.glob("lib/win32ole*"), "ext/win32ole/lib")
    when "open3"
      sync_lib gem, upstream
      rm_rf("lib/open3/jruby_windows.rb")
    when "syntax_suggest"
      sync_lib gem, upstream
      rm_rf(%w[spec/syntax_suggest libexec/syntax_suggest])
      cp_r("#{upstream}/spec", "spec/syntax_suggest")
      cp_r("#{upstream}/exe/syntax_suggest", "libexec/syntax_suggest")
    when "prism"
      rm_rf(%w[test/prism prism])

      cp_r("#{upstream}/ext/prism", "prism")
      cp_r("#{upstream}/lib/.", "lib")
      cp_r("#{upstream}/test/prism", "test")
      cp_r("#{upstream}/src/.", "prism")

      cp_r("#{upstream}/prism.gemspec", "lib/prism")
      cp_r("#{upstream}/include/prism/.", "prism")
      cp_r("#{upstream}/include/prism.h", "prism")

      cp_r("#{upstream}/config.yml", "prism/")
      cp_r("#{upstream}/templates", "prism/")
      rm_rf("prism/templates/javascript")
      rm_rf("prism/templates/java")
      rm_rf("prism/templates/rbi")
      rm_rf("prism/templates/sig")

      rm("prism/extconf.rb")
    else
      sync_lib gem, upstream
    end

    # Architecture-dependent files must not pollute libdir.
    rm_rf(Dir["lib/**/*.#{RbConfig::CONFIG['DLEXT']}"])
    replace_rdoc_ref_all
  end

  def ignore_file_pattern_for(gem)
    patterns = []

    # Common patterns
    patterns << %r[\A(?:
      [^/]+ # top-level entries
      |\.git.*
      |bin/.*
      |ext/.*\.java
      |rakelib/.*
      |test/(?:lib|fixtures)/.*
      |tool/(?!bundler/).*
    )\z]mx

    # Gem-specific patterns
    case gem
    when nil
    end&.tap do |pattern|
      patterns << pattern
    end

    Regexp.union(*patterns)
  end

  def message_filter(repo, sha, input: ARGF)
    log = input.read
    log.delete!("\r")
    log << "\n" if !log.end_with?("\n")
    repo_url = "https://github.com/#{repo}"

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
    if log and !log.empty?
      log.sub!(/(?<=\n)\n+\z/, '') # drop empty lines at the last
      conv[log]
      log.sub!(/(?:(\A\s*)|\s*\n)(?=((?i:^Co-authored-by:.*\n?)+)?\Z)/) {
        ($~.begin(1) ? "" : "\n\n") + commit_url + ($~.begin(2) ? "\n" : "")
      }
    else
      log = commit_url
    end
    puts subject, "\n", log
  end

  # Returns commit list as array of [commit_hash, subject].
  def commits_in_ranges(gem, repo, default_branch, ranges)
    # If -a is given, discover all commits since the last picked commit
    if ranges == true
      # \r? needed in the regex in case the commit has windows-style line endings (because e.g. we're running
      # tests on Windows)
      pattern = "https://github\.com/#{Regexp.quote(repo)}/commit/([0-9a-f]+)\r?$"
      log = IO.popen(%W"git log -E --grep=#{pattern} -n1 --format=%B", "rb", &:read)
      ranges = ["#{log[%r[#{pattern}\n\s*(?i:co-authored-by:.*)*\s*\Z], 1]}..#{gem}/#{default_branch}"]
    end

    # Parse a given range with git log
    ranges.flat_map do |range|
      unless range.include?("..")
        range = "#{range}~1..#{range}"
      end

      IO.popen(%W"git log --format=%H,%s #{range} --", "rb") do |f|
        f.read.split("\n").reverse.map{|commit| commit.split(',', 2)}
      end
    end
  end

  #--
  # Following methods used by sync_default_gems_with_commits return
  # true:  success
  # false: skipped
  # nil:   failed
  #++

  def resolve_conflicts(gem, sha, edit)
    # Skip this commit if everything has been removed as `ignored_paths`.
    changes = pipe_readlines(%W"git status --porcelain -z")
    if changes.empty?
      puts "Skip empty commit #{sha}"
      return false
    end

    # We want to skip DD: deleted by both.
    deleted = changes.grep(/^DD /) {$'}
    system(*%W"git rm -f --", *deleted) unless deleted.empty?

    # Import UA: added by them
    added = changes.grep(/^UA /) {$'}
    system(*%W"git add --", *added) unless added.empty?

    # Discover unmerged files
    # AU: unmerged, added by us
    # DU: unmerged, deleted by us
    # UU: unmerged, both modified
    # AA: unmerged, both added
    conflict = changes.grep(/\A(?:.U|AA) /) {$'}
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

  def preexisting?(base, file)
    system(*%w"git cat-file -e", "#{base}:#{file}", err: File::NULL)
  end

  def filter_pickup_files(changed, ignore_file_pattern, base)
    toplevels = {}
    remove = []
    ignore = []
    changed = changed.reject do |f|
      case
      when toplevels.fetch(top = f[%r[\A[^/]+(?=/|\z)]m]) {
             remove << top if toplevels[top] = !preexisting?(base, top)
           }
        # Remove any new top-level directories.
        true
      when ignore_file_pattern.match?(f)
        # Forcibly reset any changes matching ignore_file_pattern.
        (preexisting?(base, f) ? ignore : remove) << f
      end
    end
    return changed, remove, ignore
  end

  def pickup_files(gem, changed, picked)
    # Forcibly remove any files that we don't want to copy to this
    # repository.

    ignore_file_pattern = ignore_file_pattern_for(gem)

    base = picked ? "HEAD~" : "HEAD"
    changed, remove, ignore = filter_pickup_files(changed, ignore_file_pattern, base)

    unless remove.empty?
      puts "Remove added files: #{remove.join(', ')}"
      system(*%w"git rm -fr --", *remove)
      if picked
        system(*%w"git commit --amend --no-edit --", *remove, %i[out err] => File::NULL)
      end
    end

    unless ignore.empty?
      puts "Reset ignored files: #{ignore.join(', ')}"
      system(*%W"git rm -r --", *ignore)
      ignore.each {|f| system(*%W"git checkout -f", base, "--", f)}
    end

    if changed.empty?
      return nil
    end

    return changed
  end

  def pickup_commit(gem, sha, edit)
    # Attempt to cherry-pick a commit
    result = IO.popen(%W"git cherry-pick #{sha}", "rb", &:read)
    picked = $?.success?
    if result =~ /nothing\ to\ commit/
      `git reset`
      puts "Skip empty commit #{sha}"
      return false
    end

    # Skip empty commits
    if result.empty?
      return false
    end

    if picked
      changed = pipe_readlines(%w"git diff-tree --name-only -r -z HEAD~..HEAD --")
    else
      changed = pipe_readlines(%w"git diff --name-only -r -z HEAD --")
    end

    # Pick up files to merge.
    unless changed = pickup_files(gem, changed, picked)
      puts "Skip commit #{sha} only for tools or toplevel"
      if picked
        `git reset --hard HEAD~`
      else
        `git cherry-pick --abort`
      end
      return false
    end

    # If the cherry-pick attempt failed, try to resolve conflicts.
    # Skip the commit, if it contains unresolved conflicts or no files to pick up.
    unless picked or resolve_conflicts(gem, sha, edit)
      `git reset` && `git checkout .` && `git clean -fd`
      return picked || nil      # Fail unless cherry-picked
    end

    # Commit cherry-picked commit
    if picked
      system(*%w"git commit --amend --no-edit")
    else
      system(*%w"git cherry-pick --continue --no-edit")
    end or return nil

    # Amend the commit if RDoc references need to be replaced
    head = `git log --format=%H -1 HEAD`.chomp
    system(*%w"git reset --quiet HEAD~ --")
    amend = replace_rdoc_ref_all
    system(*%W"git reset --quiet #{head} --")
    if amend
      `git commit --amend --no-edit --all`
    end

    return true
  end

  # NOTE: This method is also used by GitHub ruby/git.ruby-lang.org's bin/update-default-gem.sh
  # @param gem [String] A gem name, also used as a git remote name. REPOSITORIES converts it to the appropriate GitHub repository.
  # @param ranges [Array<String>] "before..after". Note that it will NOT sync "before" (but commits after that).
  # @param edit [TrueClass] Set true if you want to resolve conflicts. Obviously, update-default-gem.sh doesn't use this.
  def sync_default_gems_with_commits(gem, ranges, edit: nil)
    repo, default_branch = REPOSITORIES[gem]
    puts "Sync #{repo} with commit history."

    # Fetch the repository to be synchronized
    IO.popen(%W"git remote") do |f|
      unless f.read.split.include?(gem)
        `git remote add #{gem} https://github.com/#{repo}.git`
      end
    end
    system(*%W"git fetch --no-tags #{gem}")

    commits = commits_in_ranges(gem, repo, default_branch, ranges)

    # Ignore Merge commits and already-merged commits.
    commits.delete_if do |sha, subject|
      subject.start_with?("Merge", "Auto Merge")
    end

    if commits.empty?
      puts "No commits to pick"
      return true
    end

    puts "Try to pick these commits:"
    puts commits.map{|commit| commit.join(": ")}
    puts "----"

    failed_commits = []

    require 'shellwords'
    filter = [
      ENV.fetch('RUBY', 'ruby').shellescape,
      File.realpath(__FILE__).shellescape,
      "--message-filter",
    ]
    commits.each do |sha, subject|
      puts "Pick #{sha} from #{repo}."
      case pickup_commit(gem, sha, edit)
      when false
        next
      when nil
        failed_commits << sha
        next
      end

      puts "Update commit message: #{sha}"

      # Run this script itself (tool/sync_default_gems.rb --message-filter) as a message filter
      IO.popen({"FILTER_BRANCH_SQUELCH_WARNING" => "1"},
               %W[git filter-branch -f --msg-filter #{[filter, repo, sha].join(' ')} -- HEAD~1..HEAD],
               &:read)
      unless $?.success?
        puts "Failed to modify commit message of #{sha}"
        break
      end
    end

    unless failed_commits.empty?
      puts "---- failed commits ----"
      puts failed_commits
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

    repository, default_branch = REPOSITORIES[gem]
    author, repository = repository.split('/')

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
    REPOSITORIES.each_pair do |name, (gem)|
      next unless pattern =~ name or pattern =~ gem
      printf "%-15s https://github.com/%s\n", name, gem
    end
  when "--message-filter"
    ARGV.shift
    if ARGV.size < 2
      abort "usage: #{$0} --message-filter repository commit-hash [input...]"
    end
    message_filter(*ARGV.shift(2))
    exit
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

\e[1mImport a default library through `git clone` and `cp -rf` (git commits are lost)\e[0m
  ruby #$0 rubygems

\e[1mPick a single commit from the upstream repository\e[0m
  ruby #$0 rubygems 97e9768612

\e[1mPick a commit range from the upstream repository\e[0m
  ruby #$0 rubygems 97e9768612..9e53702832

\e[1mPick all commits since the last picked commit\e[0m
  ruby #$0 -a rubygems

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
