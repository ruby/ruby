# sync upstream github repositories to ruby repository

require 'fileutils'
include FileUtils

$repositories = {
  rubygems: 'rubygems/rubygems',
  bundler: 'rubygems/rubygems',
  rdoc: 'ruby/rdoc',
  reline: 'ruby/reline',
  json: 'flori/json',
  psych: 'ruby/psych',
  fileutils: 'ruby/fileutils',
  fiddle: 'ruby/fiddle',
  stringio: 'ruby/stringio',
  "io-console": 'ruby/io-console',
  csv: 'ruby/csv',
  webrick: 'ruby/webrick',
  dbm: 'ruby/dbm',
  gdbm: 'ruby/gdbm',
  etc: 'ruby/etc',
  date: 'ruby/date',
  zlib: 'ruby/zlib',
  fcntl: 'ruby/fcntl',
  strscan: 'ruby/strscan',
  ipaddr: 'ruby/ipaddr',
  logger: 'ruby/logger',
  prime: 'ruby/prime',
  matrix: 'ruby/matrix',
  ostruct: 'ruby/ostruct',
  irb: 'ruby/irb',
  tracer: 'ruby/tracer',
  forwardable: "ruby/forwardable",
  mutex_m: "ruby/mutex_m",
  racc: "ruby/racc",
  singleton: "ruby/singleton",
  open3: "ruby/open3",
  getoptlong: "ruby/getoptlong",
  pstore: "ruby/pstore",
  delegate: "ruby/delegate",
  benchmark: "ruby/benchmark",
  "net-pop": "ruby/net-pop",
  "net-smtp": "ruby/net-smtp",
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
  "net-imap": "ruby/net-imap",
  "net-ftp": "ruby/net-ftp",
  "net-http": "ruby/net-http",
  bigdecimal: "ruby/bigdecimal",
  optparse: "ruby/optparse",
}

def sync_default_gems(gem)
  puts "Sync #{$repositories[gem.to_sym]}"

  upstream = File.join("..", "..", $repositories[gem.to_sym])

  case gem
  when "rubygems"
    rm_rf(%w[lib/rubygems lib/rubygems.rb test/rubygems])
    cp_r(Dir.glob("#{upstream}/lib/rubygems*"), "lib")
    cp_r("#{upstream}/test/rubygems", "test")
  when "bundler"
    rm_rf(%w[lib/bundler lib/bundler.rb libexec/bundler libexec/bundle spec/bundler man/bundle* man/gemfile*])
    cp_r(Dir.glob("#{upstream}/bundler/lib/bundler*"), "lib")
    cp_r(Dir.glob("#{upstream}/bundler/exe/bundle*"), "libexec")
    cp_r("#{upstream}/bundler/bundler.gemspec", "lib/bundler")
    cp_r("#{upstream}/bundler/spec", "spec/bundler")
    cp_r(Dir.glob("#{upstream}/bundler/man/*.{1,5,1\.txt,5\.txt,ronn}"), "man")
    rm_rf(%w[spec/bundler/support/artifice/vcr_cassettes])
  when "rdoc"
    rm_rf(%w[lib/rdoc lib/rdoc.rb test/rdoc libexec/rdoc libexec/ri])
    cp_r(Dir.glob("#{upstream}/lib/rdoc*"), "lib")
    cp_r("#{upstream}/test/rdoc", "test")
    cp_r("#{upstream}/rdoc.gemspec", "lib/rdoc")
    cp_r("#{upstream}/exe/rdoc", "libexec")
    cp_r("#{upstream}/exe/ri", "libexec")
    rm_rf(%w[lib/rdoc/markdown.kpeg lib/rdoc/markdown/literals.kpeg lib/rdoc/rd/block_pager.ry lib/rdoc/rd/inline_parser.ry])
    `git checkout lib/rdoc/.document`
  when "reline"
    rm_rf(%w[lib/reline lib/reline.rb test/reline])
    cp_r(Dir.glob("#{upstream}/lib/reline*"), "lib")
    cp_r("#{upstream}/test/reline", "test")
    cp_r("#{upstream}/reline.gemspec", "lib/reline")
  when "json"
    rm_rf(%w[ext/json test/json])
    cp_r("#{upstream}/ext/json/ext", "ext/json")
    cp_r("#{upstream}/tests", "test/json")
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
    cp_r("#{upstream}/io-console.gemspec", "ext/io/console")
    `git checkout ext/io/console/depend`
  when "dbm"
    rm_rf(%w[ext/dbm test/dbm])
    cp_r("#{upstream}/ext/dbm", "ext")
    cp_r("#{upstream}/test/dbm", "test")
    cp_r("#{upstream}/dbm.gemspec", "ext/dbm")
    `git checkout ext/dbm/depend`
  when "gdbm"
    rm_rf(%w[ext/gdbm test/gdbm])
    cp_r("#{upstream}/ext/gdbm", "ext")
    cp_r("#{upstream}/test/gdbm", "test")
    cp_r("#{upstream}/gdbm.gemspec", "ext/gdbm")
    `git checkout ext/gdbm/depend ext/gdbm/README`
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
  when "net-pop"
    rm_rf(%w[lib/net/pop.rb lib/net/pop test/net/pop])
    cp_r("#{upstream}/lib/net/pop.rb", "lib/net")
    cp_r("#{upstream}/lib/net/pop", "lib/net")
    cp_r("#{upstream}/test/net/pop", "test/net")
    cp_r("#{upstream}/net-pop.gemspec", "lib/net/pop")
  when "net-smtp"
    rm_rf(%w[lib/net/smtp.rb lib/net/smtp test/net/smtp])
    cp_r("#{upstream}/lib/net/smtp.rb", "lib/net")
    cp_r("#{upstream}/lib/net/smtp", "lib/net")
    cp_r("#{upstream}/test/net/smtp", "test/net")
    cp_r("#{upstream}/net-smtp.gemspec", "lib/net/smtp")
  when "net-protocol"
    rm_rf(%w[lib/net/protocol.rb lib/net/protocol test/net/protocol])
    cp_r("#{upstream}/lib/net/protocol.rb", "lib/net")
    cp_r("#{upstream}/lib/net/protocol", "lib/net")
    cp_r("#{upstream}/test/net/protocol", "test/net")
    cp_r("#{upstream}/net-protocol.gemspec", "lib/net/protocol")
  when "net-imap"
    rm_rf(%w[lib/net/imap.rb lib/net/imap test/net/imap])
    cp_r("#{upstream}/lib/net/imap.rb", "lib/net")
    cp_r("#{upstream}/lib/net/imap", "lib/net")
    cp_r("#{upstream}/test/net/imap", "test/net")
    cp_r("#{upstream}/net-imap.gemspec", "lib/net/imap")
  when "net-ftp"
    rm_rf(%w[lib/net/ftp.rb lib/net/ftp test/net/ftp])
    cp_r("#{upstream}/lib/net/ftp.rb", "lib/net")
    cp_r("#{upstream}/lib/net/ftp", "lib/net")
    cp_r("#{upstream}/test/net/ftp", "test/net")
    cp_r("#{upstream}/net-ftp.gemspec", "lib/net/ftp")
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
  else
    sync_lib gem
  end
end

IGNORE_FILE_PATTERN =
  /\A(?:[A-Z]\w*\.(?:md|txt)
  |[^\/]+\.yml
  |\.git.*
  |[A-Z]\w+file
  )\z/x

def sync_default_gems_with_commits(gem, ranges, edit: nil)
  puts "Sync #{$repositories[gem.to_sym]} with commit history."

  IO.popen(%W"git remote") do |f|
    unless f.read.split.include?(gem)
      `git remote add #{gem} git@github.com:#{$repositories[gem.to_sym]}.git`
    end
  end
  system(*%W"git fetch --no-tags #{gem}")

  commits = ranges.flat_map do |range|
    unless range.include?("..")
      range = "#{range}~1..#{range}"
    end

    IO.popen(%W"git log --format=%H,%s #{range}") do |f|
      f.read.split("\n").reverse.map{|commit| commit.split(',', 2)}
    end
  end

  # Ignore Merge commit and insufficiency commit for ruby core repository.
  commits.delete_if do |sha, subject|
    files = IO.popen(%W"git diff-tree --no-commit-id --name-only -r #{sha}", &:readlines)
    subject =~ /^Merge/ || subject =~ /^Auto Merge/ || files.all?{|file| file =~ IGNORE_FILE_PATTERN}
  end

  puts "Try to pick these commits:"
  puts commits.map{|commit| commit.join(": ")}.join("\n")
  puts "----"

  failed_commits = []

  ENV["FILTER_BRANCH_SQUELCH_WARNING"] = "1"

  commits.each do |sha, subject|
    puts "Pick #{sha} from #{$repositories[gem.to_sym]}."

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
        system(*%W"git checkout HEAD --", *ignore)
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

    prefix = "[#{($repositories[gem.to_sym])}]".gsub(/\//, '\/')
    suffix = "https://github.com/#{($repositories[gem.to_sym])}/commit/#{sha[0,10]}"
    `git filter-branch -f --msg-filter 'sed "1s/^/#{prefix} /" && echo && echo #{suffix}' -- HEAD~1..HEAD`
    unless $?.success?
      puts "Failed to modify commit message of #{sha}"
      break
    end
  end

  unless failed_commits.empty?
    puts "---- failed commits ----"
    puts failed_commits
  end
end

def sync_lib(repo)
  unless File.directory?("../#{repo}")
    abort %[Expected '../#{repo}' \(#{File.expand_path("../#{repo}")}\) to be a directory, but it wasn't.]
  end
  rm_rf(["lib/#{repo}.rb", "lib/#{repo}/*", "test/test_#{repo}.rb"])
  cp_r(Dir.glob("../#{repo}/lib/*"), "lib")
  tests = if File.directory?("test/#{repo}")
            "test/#{repo}"
          else
            "test/test_#{repo}.rb"
          end
  cp_r("../#{repo}/#{tests}", "test") if File.exist?("../#{repo}/#{tests}")
  gemspec = if File.directory?("lib/#{repo}")
              "lib/#{repo}/#{repo}.gemspec"
            else
              "lib/#{repo}.gemspec"
            end
  cp_r("../#{repo}/#{repo}.gemspec", "#{gemspec}")
end

def update_default_gems(gem)

  author, repository = $repositories[gem.to_sym].split('/')

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
    $repositories.keys.each{|gem| update_default_gems(gem.to_s)}
  end
when "all"
  $repositories.keys.each{|gem| sync_default_gems(gem.to_s)}
when "list"
  ARGV.shift
  pattern = Regexp.new(ARGV.join('|'))
  $repositories.each_pair do |name, gem|
    next unless pattern =~ name or pattern =~ gem
    printf "%-15s https://github.com/%s\n", name, gem
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

\e[1mList known libraries\e[0m
  ruby #$0 list

\e[1mList known libraries matching with patterns\e[0m
  ruby #$0 list read
    HELP

  exit
else
  if ARGV[0] == "-e"
    edit = true
    ARGV.shift
  end
  gem = ARGV.shift
  if ARGV[0]
    sync_default_gems_with_commits(gem, ARGV, edit: edit)
  else
    sync_default_gems(gem)
  end
end
