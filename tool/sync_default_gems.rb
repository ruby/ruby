# sync following repositories to ruby repository
#
# * https://github.com/rubygems/rubygems
# * https://github.com/bundler/bundler
# * https://github.com/ruby/rdoc
# * https://github.com/ruby/reline
# * https://github.com/flori/json
# * https://github.com/ruby/psych
# * https://github.com/ruby/fileutils
# * https://github.com/ruby/fiddle
# * https://github.com/ruby/stringio
# * https://github.com/ruby/io-console
# * https://github.com/ruby/csv
# * https://github.com/ruby/webrick
# * https://github.com/ruby/dbm
# * https://github.com/ruby/gdbm
# * https://github.com/ruby/sdbm
# * https://github.com/ruby/etc
# * https://github.com/ruby/date
# * https://github.com/ruby/zlib
# * https://github.com/ruby/fcntl
# * https://github.com/ruby/scanf
# * https://github.com/ruby/cmath
# * https://github.com/ruby/strscan
# * https://github.com/ruby/ipaddr
# * https://github.com/ruby/logger
# * https://github.com/ruby/prime
# * https://github.com/ruby/matrix
# * https://github.com/ruby/ostruct
# * https://github.com/ruby/rexml
# * https://github.com/ruby/rss
# * https://github.com/ruby/irb
# * https://github.com/ruby/sync
# * https://github.com/ruby/tracer
# * https://github.com/ruby/shell
# * https://github.com/ruby/forwardable
# * https://github.com/ruby/thwait
# * https://github.com/ruby/e2mmap
# * https://github.com/ruby/mutex_m
# * https://github.com/ruby/racc
#

require 'fileutils'
include FileUtils

$repositories = {
  rubygems: 'rubygems/rubygems',
  bundler: 'bundler/bundler',
  rdoc: 'ruby/rdoc',
  reline: 'ruby/reline',
  json: 'flori/json',
  psych: 'ruby/psych',
  fileutils: 'ruby/fileutils',
  fiddle: 'ruby/fiddle',
  stringio: 'ruby/stringio',
  ioconsole: 'ruby/io-console',
  csv: 'ruby/csv',
  webrick: 'ruby/webrick',
  dbm: 'ruby/dbm',
  gdbm: 'ruby/gdbm',
  sdbm: 'ruby/sdbm',
  etc: 'ruby/etc',
  date: 'ruby/date',
  zlib: 'ruby/zlib',
  fcntl: 'ruby/fcntl',
  scanf: 'ruby/scanf',
  cmath: 'ruby/cmath',
  strscan: 'ruby/strscan',
  ipaddr: 'ruby/ipaddr',
  logger: 'ruby/logger',
  prime: 'ruby/prime',
  matrix: 'ruby/matrix',
  ostruct: 'ruby/ostruct',
  rexml: 'ruby/rexml',
  rss: 'ruby/rss',
  irb: 'ruby/irb',
  sync: 'ruby/sync',
  tracer: 'ruby/tracer',
  shell: 'ruby/shell',
  forwardable: "ruby/forwardable",
  thwait: "ruby/thwait",
  e2mmap: "ruby/e2mmap",
  mutex_m: "ruby/mutex_m",
  racc: "ruby/racc"
}

def sync_default_gems(gem)
  puts "Sync #{$repositories[gem.to_sym]}"

  upstream = File.join("..", "..", $repositories[gem.to_sym])

  case gem
  when "rubygems"
    rm_rf(%w[lib/rubygems* test/rubygems])
    cp_r(Dir.glob("#{upstream}/lib/rubygems*"), "lib")
    cp_r("#{upstream}/test/rubygems", "test")
  when "bundler"
    rm_rf(%w[lib/bundler* libexec/bundler libexec/bundle spec/bundler man/bundle* man/gemfile*])
    cp_r(Dir.glob("#{upstream}/lib/bundler*"), "lib")
    cp_r(Dir.glob("#{upstream}/exe/bundle*"), "libexec")
    cp_r("#{upstream}/bundler.gemspec", "lib/bundler")
    cp_r("#{upstream}/spec", "spec/bundler")
    cp_r(Dir.glob("#{upstream}/man/*.{1,5,1\.txt,5\.txt,ronn}"), "man")
    rm_rf(%w[spec/bundler/support/artifice/vcr_cassettes])
  when "rdoc"
    rm_rf(%w[lib/rdoc* test/rdoc libexec/rdoc libexec/ri])
    cp_r(Dir.glob("#{upstream}/lib/rdoc*"), "lib")
    cp_r("#{upstream}/test/rdoc", "test")
    cp_r("#{upstream}/rdoc.gemspec", "lib/rdoc")
    cp_r("#{upstream}/exe/rdoc", "libexec")
    cp_r("#{upstream}/exe/ri", "libexec")
    rm_rf(%w[lib/rdoc/markdown.kpeg lib/rdoc/markdown/literals.kpeg lib/rdoc/rd/block_parser.ry lib/rdoc/rd/inline_parser.ry])
    `git checkout lib/rdoc/.document`
  when "reline"
    rm_rf(%w[lib/reline* test/reline])
    cp_r(Dir.glob("#{upstream}/lib/reline*"), "lib")
    cp_r("#{upstream}/test", "test/reline")
    cp_r("#{upstream}/reline.gemspec", "lib/reline")
  when "json"
    rm_rf(%w[ext/json test/json])
    cp_r("#{upstream}/ext/json/ext", "ext/json")
    cp_r("#{upstream}/tests", "test/json")
    cp_r("#{upstream}/lib", "ext/json")
    rm_rf(%[ext/json/lib/json/pure*])
    cp_r("#{upstream}/json.gemspec", "ext/json")
    rm_rf(%w[ext/json/lib/json/ext])
    `git checkout ext/json/extconf.rb ext/json/parser/prereq.mk ext/json/generator/depend ext/json/parser/depend`
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
  when "ioconsole"
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
  when "sdbm"
    rm_rf(%w[ext/sdbm test/sdbm])
    cp_r("#{upstream}/ext/sdbm", "ext")
    cp_r("#{upstream}/test/sdbm", "test")
    cp_r("#{upstream}/sdbm.gemspec", "ext/sdbm")
    `git checkout ext/sdbm/depend`
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
  when "thwait"
    rm_rf(%w[lib/thwait*])
    cp_r(Dir.glob("#{upstream}/lib/*"), "lib")
    cp_r("#{upstream}/thwait.gemspec", "lib/thwait")
  when "e2mmap"
    rm_rf(%w[lib/e2mmap*])
    cp_r(Dir.glob("#{upstream}/lib/*"), "lib")
    cp_r("#{upstream}/e2mmap.gemspec", "lib")
  when "strscan"
    rm_rf(%w[ext/strscan test/strscan])
    cp_r("#{upstream}/ext/strscan", "ext")
    cp_r("#{upstream}/test/strscan", "test")
    cp_r("#{upstream}/strscan.gemspec", "ext/strscan")
    rm_rf(%w["ext/strscan/regenc.h ext/strscan/regint.h"])
    `git checkout ext/strscan/depend`
  when "racc"
    rm_rf(%w[lib/racc* ext/racc test/racc])
    cp_r(Dir.glob("#{upstream}/lib/racc*"), "lib")
    mkdir_p("ext/racc/cparse")
    cp_r(Dir.glob("#{upstream}/ext/racc/cparse/*"), "ext/racc/cparse")
    cp_r("#{upstream}/test", "test/racc")
    `git checkout ext/racc/cparse/README`
  when "rexml", "rss", "matrix", "irb", "csv", "shell", "logger", "ostruct", "scanf", "webrick", "fileutils", "forwardable", "prime", "tracer", "ipaddr", "cmath", "mutex_m", "sync"
    sync_lib gem
  else
  end
end

IGNORE_FILE_PATTERN = /(\.travis.yml|appveyor\.yml|azure\-pipelines\.yml|\.gitignore|Gemfile|README\.md|History\.txt|Rakefile|CODE_OF_CONDUCT\.md)/

def sync_default_gems_with_commits(gem, range)
  puts "Sync #{$repositories[gem.to_sym]} with commit history."

  IO.popen(%W"git remote") do |f|
    unless f.read.split.include?(gem)
      `git remote add #{gem} git@github.com:#{$repositories[gem.to_sym]}.git`
    end
  end
  `git fetch --no-tags #{gem}`

  commits = []

  IO.popen(%W"git log --format=%H,%s #{range}") do |f|
    commits = f.read.split("\n").reverse.map{|commit| commit.split(',')}
  end

  # Ignore Merge commit and insufficiency commit for ruby core repository.
  commits.delete_if do |sha, subject|
    files = []
    IO.popen(%W"git diff-tree --no-commit-id --name-only -r #{sha}") do |f|
      files = f.read.split("\n")
    end
    subject =~ /^Merge/ || subject =~ /^Auto Merge/ || files.all?{|file| file =~ IGNORE_FILE_PATTERN}
  end

  puts "Try to pick these commits:"
  puts commits.map{|commit| commit.join(": ")}.join("\n")
  puts "----"

  failed_commits = []

  commits.each do |sha, subject|
    puts "Pick #{sha} from #{$repositories[gem.to_sym]}."

    skipped = false
    result = IO.popen(%W"git cherry-pick #{sha}").read
    if result =~ /nothing\ to\ commit/
      `git reset`
      skipped = true
      puts "Skip empty commit #{sha}"
    end
    next if skipped

    if result.empty?
      failed_commits << sha
      `git reset` && `git checkout .` && `git clean -fd`
      skipped = true
      puts "Failed to pick #{sha}"
    end
    next if skipped

    puts "Update commit message: #{sha}"

    prefix = "[#{($repositories[gem.to_sym])}]".gsub(/\//, '\/')
    suffix = "https://github.com/#{($repositories[gem.to_sym])}/commit/#{sha[0,10]}"
    `git filter-branch -f --msg-filter 'sed "1s/^/#{prefix} /" && echo && echo #{suffix}' -- HEAD~1..HEAD`
    unless $?.success?
      puts "Failed to modify commit message of #{sha}"
      break
    end
  end

  puts "---- failed commits ----"
  puts failed_commits
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
  cp_r("../#{repo}/#{tests}", "test")
  gemspec = if File.directory?("lib/#{repo}")
              "lib/#{repo}/#{repo}.gemspec"
            else
              "lib/#{repo}.gemspec"
            end
  cp_r("../#{repo}/#{repo}.gemspec", "#{gemspec}")
end

def update_default_gems(gem)
  author, repository = $repositories[gem.to_sym].split('/')

  unless File.exist?("../../#{author}/#{repository}")
    mkdir_p("../../#{author}")
    `git clone git@github.com:#{author}/#{repository}.git ../../#{author}/#{repository}`
  end

  Dir.chdir("../../#{author}/#{repository}") do
    unless `git remote`.match(/ruby\-core/)
      `git remote add ruby-core git@github.com:ruby/ruby.git`
      `git fetch ruby-core`
      `git co ruby-core/trunk`
      `git branch ruby-core`
    end
    `git co ruby-core`
    `git fetch ruby-core trunk`
    `git rebase ruby-core/trunk`
    `git co master`
    `git stash`
    `git pull --rebase`
  end
end

case ARGV[0]
when "up"
  $repositories.keys.each{|gem| update_default_gems(gem.to_s)}
when "all"
  $repositories.keys.each{|gem| sync_default_gems(gem.to_s)}
else
  if ARGV[1]
    sync_default_gems_with_commits(ARGV[0], ARGV[1])
  else
    sync_default_gems(ARGV[0])
  end
end
