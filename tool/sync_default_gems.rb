#!/usr/bin/env ruby
# sync upstream github repositories to ruby repository

require 'fileutils'
include FileUtils

REPOSITORIES = {
  rubygems: 'rubygems/rubygems',
  rdoc: 'ruby/rdoc',
  reline: 'ruby/reline',
  json: 'flori/json',
  psych: 'ruby/psych',
  fileutils: 'ruby/fileutils',
  fiddle: 'ruby/fiddle',
  stringio: 'ruby/stringio',
  "io-console": 'ruby/io-console',
  "io-nonblock": 'ruby/io-nonblock',
  "io-wait": 'ruby/io-wait',
  csv: 'ruby/csv',
  etc: 'ruby/etc',
  date: 'ruby/date',
  zlib: 'ruby/zlib',
  fcntl: 'ruby/fcntl',
  strscan: 'ruby/strscan',
  ipaddr: 'ruby/ipaddr',
  logger: 'ruby/logger',
  ostruct: 'ruby/ostruct',
  irb: 'ruby/irb',
  forwardable: "ruby/forwardable",
  mutex_m: "ruby/mutex_m",
  racc: "ruby/racc",
  singleton: "ruby/singleton",
  open3: "ruby/open3",
  getoptlong: "ruby/getoptlong",
  pstore: "ruby/pstore",
  delegate: "ruby/delegate",
  benchmark: "ruby/benchmark",
  cgi: "ruby/cgi",
  readline: "ruby/readline",
  "readline-ext": "ruby/readline-ext",
  observer: "ruby/observer",
  timeout: "ruby/timeout",
  yaml: "ruby/yaml",
  uri: "ruby/uri",
  openssl: "ruby/openssl",
  did_you_mean: "ruby/did_you_mean",
  weakref: "ruby/weakref",
  tempfile: "ruby/tempfile",
  tmpdir: "ruby/tmpdir",
  English: "ruby/English",
  "net-protocol": "ruby/net-protocol",
  "net-http": "ruby/net-http",
  bigdecimal: "ruby/bigdecimal",
  optparse: "ruby/optparse",
  set: "ruby/set",
  find: "ruby/find",
  rinda: "ruby/rinda",
  erb: "ruby/erb",
  nkf: "ruby/nkf",
  tsort: "ruby/tsort",
  abbrev: "ruby/abbrev",
  shellwords: "ruby/shellwords",
  base64: "ruby/base64",
  syslog: "ruby/syslog",
  "open-uri": "ruby/open-uri",
  securerandom: "ruby/securerandom",
  resolv: "ruby/resolv",
  "resolv-replace": "ruby/resolv-replace",
  time: "ruby/time",
  pp: "ruby/pp",
  prettyprint: "ruby/prettyprint",
  drb: "ruby/drb",
  pathname: "ruby/pathname",
  digest: "ruby/digest",
  error_highlight: "ruby/error_highlight",
  un: "ruby/un",
  win32ole: "ruby/win32ole",
}

# We usually don't use this. Please consider using #sync_default_gems_with_commits instead.
def sync_default_gems(gem)
  repo = REPOSITORIES[gem.to_sym]
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

      line.gsub("bundler.gemspec", "lib/bundler/bundler.gemspec").gsub('"exe"', '"libexec"')
    end.compact.join
    File.write("lib/bundler/bundler.gemspec", gemspec_content)

    cp_r("#{upstream}/bundler/spec", "spec/bundler")
    cp_r(Dir.glob("#{upstream}/bundler/tool/bundler/dev_gems*"), "tool/bundler")
    cp_r(Dir.glob("#{upstream}/bundler/tool/bundler/test_gems*"), "tool/bundler")
    cp_r(Dir.glob("#{upstream}/bundler/tool/bundler/rubocop_gems*"), "tool/bundler")
    cp_r(Dir.glob("#{upstream}/bundler/tool/bundler/standard_gems*"), "tool/bundler")
    rm_rf(%w[spec/bundler/support/artifice/vcr_cassettes])
    license_files = %w[
      lib/bundler/vendor/thor/LICENSE.md
      lib/rubygems/resolver/molinillo/LICENSE
      lib/bundler/vendor/molinillo/LICENSE
      lib/bundler/vendor/connection_pool/LICENSE
      lib/bundler/vendor/net-http-persistent/README.rdoc
      lib/bundler/vendor/fileutils/LICENSE.txt
      lib/bundler/vendor/tsort/LICENSE.txt
      lib/bundler/vendor/uri/LICENSE.txt
      lib/rubygems/optparse/COPYING
      lib/rubygems/tsort/LICENSE.txt
    ]
    rm_rf license_files
  when "rdoc"
    rm_rf(%w[lib/rdoc lib/rdoc.rb test/rdoc libexec/rdoc libexec/ri])
    cp_r(Dir.glob("#{upstream}/lib/rdoc*"), "lib")
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
    cp_r("#{upstream}/VERSION", "ext/json")
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
    `git checkout ext/psych/depend`
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
    rm_rf(%w["ext/strscan/regenc.h ext/strscan/regint.h"])
    `git checkout ext/strscan/depend`
  when "racc"
    rm_rf(%w[lib/racc lib/racc.rb ext/racc test/racc])
    cp_r(Dir.glob("#{upstream}/lib/racc*"), "lib")
    mkdir_p("ext/racc/cparse")
    cp_r(Dir.glob("#{upstream}/ext/racc/cparse/*"), "ext/racc/cparse")
    cp_r("#{upstream}/test", "test/racc")
    cp_r("#{upstream}/racc.gemspec", "lib/racc")
    rm_rf("test/racc/lib")
    rm_rf("lib/racc/cparse-jruby.jar")
    `git checkout ext/racc/cparse/README ext/racc/cparse/depend`
  when "cgi"
    rm_rf(%w[lib/cgi.rb lib/cgi ext/cgi test/cgi])
    cp_r("#{upstream}/ext/cgi", "ext")
    cp_r("#{upstream}/lib", ".")
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
  when "readline-ext"
    rm_rf(%w[ext/readline test/readline])
    cp_r("#{upstream}/ext/readline", "ext")
    cp_r("#{upstream}/test/readline", "test")
    cp_r("#{upstream}/readline-ext.gemspec", "ext/readline")
    `git checkout ext/readline/depend`
  when "did_you_mean"
    rm_rf(%w[lib/did_you_mean lib/did_you_mean.rb test/did_you_mean])
    cp_r(Dir.glob("#{upstream}/lib/did_you_mean*"), "lib")
    cp_r("#{upstream}/did_you_mean.gemspec", "lib/did_you_mean")
    cp_r("#{upstream}/test", "test/did_you_mean")
    rm_rf(%w[test/did_you_mean/tree_spell/test_explore.rb])
  when "erb"
    rm_rf(%w[lib/erb* test/erb libexec/erb])
    cp_r("#{upstream}/lib/erb.rb", "lib")
    cp_r("#{upstream}/test/erb", "test")
    cp_r("#{upstream}/erb.gemspec", "lib")
    cp_r("#{upstream}/libexec/erb", "libexec")
  when "nkf"
    rm_rf(%w[ext/nkf test/nkf])
    cp_r("#{upstream}/ext/nkf", "ext")
    cp_r("#{upstream}/lib", "ext/nkf")
    cp_r("#{upstream}/test/nkf", "test")
    cp_r("#{upstream}/nkf.gemspec", "ext/nkf")
    `git checkout ext/nkf/depend`
  when "syslog"
    rm_rf(%w[ext/syslog test/syslog test/test_syslog.rb])
    cp_r("#{upstream}/ext/syslog", "ext")
    cp_r("#{upstream}/lib", "ext/syslog")
    cp_r("#{upstream}/test/syslog", "test")
    cp_r("#{upstream}/test/test_syslog.rb", "test")
    cp_r("#{upstream}/syslog.gemspec", "ext/syslog")
    `git checkout ext/syslog/depend`
  when "bigdecimal"
    rm_rf(%w[ext/bigdecimal test/bigdecimal])
    cp_r("#{upstream}/ext/bigdecimal", "ext")
    cp_r("#{upstream}/sample", "ext/bigdecimal")
    cp_r("#{upstream}/lib", "ext/bigdecimal")
    cp_r("#{upstream}/test/bigdecimal", "test")
    cp_r("#{upstream}/bigdecimal.gemspec", "ext/bigdecimal")
    `git checkout ext/bigdecimal/depend`
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
    cp_r("#{upstream}/test", ".")
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
  else
    sync_lib gem, upstream
  end
end

IGNORE_FILE_PATTERN =
  /\A(?:[A-Z]\w*\.(?:md|txt)
  |[^\/]+\.yml
  |\.git.*
  |[A-Z]\w+file
  |COPYING
  |rakelib\/
  )\z/x

def message_filter(repo, sha)
  log = STDIN.read
  log.delete!("\r")
  url = "https://github.com/#{repo}"
  print "[#{repo}] ", log.gsub(/\b(?i:fix) +\K#(?=\d+\b)|\(\K#(?=\d+\))|\bGH-(?=\d+\b)/) {
    "#{url}/pull/"
  }.gsub(%r{(?<![-\[\](){}\w@/])(?:(\w+(?:-\w+)*/\w+(?:-\w+)*)@)?(\h{10,40})\b}) {|c|
    "https://github.com/#{$1 || repo}/commit/#{$2[0,12]}"
  }.sub(/\s*(?=(?i:\nCo-authored-by:.*)*\Z)/) {
    "\n\n" "#{url}/commit/#{sha[0,10]}\n"
  }
end

# NOTE: This method is also used by ruby-commit-hook/bin/update-default-gem.sh
# @param gem [String] A gem name, also used as a git remote name. REPOSITORIES converts it to the appropriate GitHub repository.
# @param ranges [Array<String>] "before..after". Note that it will NOT sync "before" (but commits after that).
# @param edit [TrueClass] Set true if you want to resolve conflicts. Obviously, update-default-gem.sh doesn't use this.
def sync_default_gems_with_commits(gem, ranges, edit: nil)
  repo = REPOSITORIES[gem.to_sym]
  puts "Sync #{repo} with commit history."

  IO.popen(%W"git remote") do |f|
    unless f.read.split.include?(gem)
      `git remote add #{gem} git@github.com:#{repo}.git`
    end
  end
  system(*%W"git fetch --no-tags #{gem}")

  if ranges == true
    pattern = "https://github\.com/#{Regexp.quote(repo)}/commit/([0-9a-f]+)$"
    log = IO.popen(%W"git log -E --grep=#{pattern} -n1 --format=%B", &:read)
    ranges = ["#{log[%r[#{pattern}\n\s*(?i:co-authored-by:.*)*\s*\Z], 1]}..#{gem}/master"]
  end

  commits = ranges.flat_map do |range|
    unless range.include?("..")
      range = "#{range}~1..#{range}"
    end

    IO.popen(%W"git log --format=%H,%s #{range} --") do |f|
      f.read.split("\n").reverse.map{|commit| commit.split(',', 2)}
    end
  end

  # Ignore Merge commit and insufficiency commit for ruby core repository.
  commits.delete_if do |sha, subject|
    files = IO.popen(%W"git diff-tree --no-commit-id --name-only -r #{sha}", &:readlines)
    subject =~ /^Merge/ || subject =~ /^Auto Merge/ || files.all?{|file| file =~ IGNORE_FILE_PATTERN}
  end

  if commits.empty?
    puts "No commits to pick"
    return true
  end

  puts "Try to pick these commits:"
  puts commits.map{|commit| commit.join(": ")}
  puts "----"

  failed_commits = []

  ENV["FILTER_BRANCH_SQUELCH_WARNING"] = "1"

  require 'shellwords'
  filter = [
    ENV.fetch('RUBY', 'ruby').shellescape,
    File.realpath(__FILE__).shellescape,
    "--message-filter",
  ]
  commits.each do |sha, subject|
    puts "Pick #{sha} from #{repo}."

    skipped = false
    result = IO.popen(%W"git cherry-pick #{sha}", &:read)
    if result =~ /nothing\ to\ commit/
      `git reset`
      skipped = true
      puts "Skip empty commit #{sha}"
    end
    next if skipped

    if result.empty?
      skipped = true
    elsif /^CONFLICT/ =~ result
      result = IO.popen(%W"git status --porcelain", &:readlines).each(&:chomp!)
      result.map! {|line| line[/^.U (.*)/, 1]}
      result.compact!
      ignore, conflict = result.partition {|name| IGNORE_FILE_PATTERN =~ name}
      unless ignore.empty?
        system(*%W"git reset HEAD --", *ignore)
        File.unlink(*ignore)
        ignore = IO.popen(%W"git status --porcelain" + ignore, &:readlines).map! {|line| line[/^.. (.*)/, 1]}
        system(*%W"git checkout HEAD --", *ignore) unless ignore.empty?
      end
      unless conflict.empty?
        if edit
          case
          when (editor = ENV["GIT_EDITOR"] and !editor.empty?)
          when (editor = `git config core.editor` and (editor.chomp!; !editor.empty?))
          end
          if editor
            system([editor, conflict].join(' '))
          end
        end
      end
      skipped = !system({"GIT_EDITOR"=>"true"}, *%W"git cherry-pick --no-edit --continue")
    end

    if skipped
      failed_commits << sha
      `git reset` && `git checkout .` && `git clean -fd`
      puts "Failed to pick #{sha}"
      next
    end

    puts "Update commit message: #{sha}"

    IO.popen(%W[git filter-branch -f --msg-filter #{[filter, repo, sha].join(' ')} -- HEAD~1..HEAD], &:read)
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

def update_default_gems(gem)

  author, repository = REPOSITORIES[gem.to_sym].split('/')

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
    `git checkout master`
    `git fetch origin master`
    `git rebase origin/master`
  end
end

case ARGV[0]
when "up"
  if ARGV[1]
    update_default_gems(ARGV[1])
  else
    REPOSITORIES.keys.each{|gem| update_default_gems(gem.to_s)}
  end
when "all"
  REPOSITORIES.keys.each{|gem| sync_default_gems(gem.to_s)}
when "list"
  ARGV.shift
  pattern = Regexp.new(ARGV.join('|'))
  REPOSITORIES.each_pair do |name, gem|
    next unless pattern =~ name or pattern =~ gem
    printf "%-15s https://github.com/%s\n", name, gem
  end
when "--message-filter"
  ARGV.shift
  abort unless ARGV.size == 2
  message_filter(*ARGV)
  exit
when nil, "-h", "--help"
    puts <<-HELP
\e[1mSync with upstream code of default libraries\e[0m

\e[1mImport a default library through `git clone` and `cp -rf` (git commits are lost)\e[0m
  ruby #$0 rubygems

\e[1mPick a single commit from the upstream repository\e[0m
  ruby #$0 rubygems 97e9768612

\e[1mPick a commit range from the upstream repository\e[0m
  ruby #$0 rubygems 97e9768612..9e53702832

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
end
