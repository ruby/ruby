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
    FileUtils.rm_rf(%w[lib/rubygems* test/rubygems])
    `cp -r #{upstream}/lib/rubygems* ./lib`
    `cp -r #{upstream}/test/rubygems ./test`
  when "bundler"
    FileUtils.rm_rf(%w[lib/bundler* libexec/bundler libexec/bundle spec/bundler man/bundle* man/gemfile*])
    `cp -r #{upstream}/lib/bundler* ./lib`
    `cp -r #{upstream}/exe/bundle* ./libexec`
    `cp #{upstream}/bundler.gemspec ./lib/bundler`
    `cp -r #{upstream}/spec spec/bundler`
    `cp -r #{upstream}/man/*.{1,5,1\.txt,5\.txt,ronn} ./man`
    FileUtils.rm_rf(%w[spec/bundler/support/artifice/vcr_cassettes])
  when "rdoc"
    FileUtils.rm_rf(%w[lib/rdoc* test/rdoc libexec/rdoc libexec/ri])
    `cp -rf #{upstream}/lib/rdoc* ./lib`
    `cp -rf #{upstream}/test test/rdoc`
    `cp #{upstream}/rdoc.gemspec ./lib/rdoc`
    `cp -rf #{upstream}/exe/rdoc ./libexec`
    `cp -rf #{upstream}/exe/ri ./libexec`
    FileUtils.rm_rf(%w[lib/rdoc/markdown.kpeg lib/rdoc/markdown/literals.kpeg lib/rdoc/rd/block_parser.ry lib/rdoc/rd/inline_parser.ry])
    `git checkout lib/rdoc/.document`
  when "reline"
    FileUtils.rm_rf(%w[lib/reline* test/reline])
    `cp -rf #{upstream}/lib/reline* ./lib`
    `cp -rf #{upstream}/test test/reline`
    `cp #{upstream}/reline.gemspec ./lib/reline`
  when "json"
    FileUtils.rm_rf(%w[ext/json test/json])
    `cp -rf #{upstream}/ext/json/ext ext/json`
    `cp -rf #{upstream}/tests test/json`
    `cp -rf #{upstream}/lib ext/json`
    FileUtils.rm_rf(%[ext/json/lib/json/pure*])
    `cp #{upstream}/json.gemspec ext/json`
    FileUtils.rm_rf(%w[ext/json/lib/json/ext])
    `git checkout ext/json/extconf.rb ext/json/parser/prereq.mk ext/json/generator/depend ext/json/parser/depend`
  when "psych"
    FileUtils.rm_rf(%w[ext/psych test/psych])
    `cp -rf #{upstream}/ext/psych ./ext`
    `cp -rf #{upstream}/lib ./ext/psych`
    `cp -rf #{upstream}/test/psych ./test`
    FileUtils.rm_rf(%w[ext/psych/lib/org ext/psych/lib/psych.jar ext/psych/lib/psych_jars.rb])
    FileUtils.rm_rf(%w[ext/psych/lib/psych.{bundle,so} ext/psych/lib/2.*])
    FileUtils.rm_rf(["ext/psych/yaml/LICENSE"])
    `cp #{upstream}/psych.gemspec ext/psych/`
    `git checkout ext/psych/depend`
  when "fiddle"
    FileUtils.rm_rf(%w[ext/fiddle test/fiddle])
    `cp -rf #{upstream}/ext/fiddle ext`
    `cp -rf #{upstream}/lib ext/fiddle`
    `cp -rf #{upstream}/test/fiddle test`
    `cp -f #{upstream}/fiddle.gemspec ext/fiddle`
    `git checkout ext/fiddle/depend`
    FileUtils.rm_rf(%w[ext/fiddle/lib/fiddle.{bundle,so}])
  when "stringio"
    FileUtils.rm_rf(%w[ext/stringio test/stringio])
    `cp -rf #{upstream}/ext/stringio ext`
    `cp -rf #{upstream}/test/stringio test`
    `cp -f #{upstream}/stringio.gemspec ext/stringio`
    `git checkout ext/stringio/depend ext/stringio/README.md`
  when "ioconsole"
    FileUtils.rm_rf(%w[ext/io/console test/io/console])
    `cp -rf #{upstream}/ext/io/console ext/io`
    `cp -rf #{upstream}/test/io/console test/io`
    `mkdir -p ext/io/console/lib`
    `cp -rf #{upstream}/lib/io/console ext/io/console/lib`
    `cp -f #{upstream}/io-console.gemspec ext/io/console`
    `git checkout ext/io/console/depend`
  when "dbm"
    FileUtils.rm_rf(%w[ext/dbm test/dbm])
    `cp -rf #{upstream}/ext/dbm ext`
    `cp -rf #{upstream}/test/dbm test`
    `cp -f #{upstream}/dbm.gemspec ext/dbm`
    `git checkout ext/dbm/depend`
  when "gdbm"
    FileUtils.rm_rf(%w[ext/gdbm test/gdbm])
    `cp -rf #{upstream}/ext/gdbm ext`
    `cp -rf #{upstream}/test/gdbm test`
    `cp -f #{upstream}/gdbm.gemspec ext/gdbm`
    `git checkout ext/gdbm/depend ext/gdbm/README`
  when "sdbm"
    FileUtils.rm_rf(%w[ext/sdbm test/sdbm])
    `cp -rf #{upstream}/ext/sdbm ext`
    `cp -rf #{upstream}/test/sdbm test`
    `cp -f #{upstream}/sdbm.gemspec ext/sdbm`
    `git checkout ext/sdbm/depend`
  when "etc"
    FileUtils.rm_rf(%w[ext/etc test/etc])
    `cp -rf #{upstream}/ext/etc ext`
    `cp -rf #{upstream}/test/etc test`
    `cp -f #{upstream}/etc.gemspec ext/etc`
    `git checkout ext/etc/depend`
  when "date"
    FileUtils.rm_rf(%w[ext/date test/date])
    `cp -rf #{upstream}/ext/date ext`
    `cp -rf #{upstream}/lib ext/date`
    `cp -rf #{upstream}/test/date test`
    `cp -f #{upstream}/date.gemspec ext/date`
    `git checkout ext/date/depend`
    FileUtils.rm_rf(["ext/date/lib/date_core.bundle"])
  when "zlib"
    FileUtils.rm_rf(%w[ext/zlib test/zlib])
    `cp -rf #{upstream}/ext/zlib ext`
    `cp -rf #{upstream}/test/zlib test`
    `cp -f #{upstream}/zlib.gemspec ext/zlib`
    `git checkout ext/zlib/depend`
  when "fcntl"
    FileUtils.rm_rf(%w[ext/fcntl])
    `cp -rf #{upstream}/ext/fcntl ext`
    `cp -f #{upstream}/fcntl.gemspec ext/fcntl`
    `git checkout ext/fcntl/depend`
  when "thwait"
    FileUtils.rm_rf(%w[lib/thwait*])
    `cp -rf #{upstream}/lib/* lib`
    `cp -rf #{upstream}/thwait.gemspec lib/thwait`
  when "e2mmap"
    FileUtils.rm_rf(%w[lib/e2mmap*])
    `cp -rf #{upstream}/lib/* lib`
    `cp -rf #{upstream}/e2mmap.gemspec lib`
  when "strscan"
    FileUtils.rm_rf(%w[ext/strscan test/strscan])
    `cp -rf #{upstream}/ext/strscan ext`
    `cp -rf #{upstream}/test/strscan test`
    `cp -f #{upstream}/strscan.gemspec ext/strscan`
    FileUtils.rm_rf(%w["ext/strscan/regenc.h ext/strscan/regint.h"])
    `git checkout ext/strscan/depend`
  when "racc"
    FileUtils.rm_rf(%w[lib/racc* ext/racc test/racc])
    `cp -rf #{upstream}/lib/racc* lib`
    `mkdir -p ext/racc/cparse`
    `cp -rf #{upstream}/ext/racc/cparse/* ext/racc/cparse`
    `cp -rf #{upstream}/test test/racc`
    `git checkout ext/racc/cparse/README`
  when "rexml", "rss", "matrix", "irb", "csv", "shell", "logger", "ostruct", "scanf", "webrick", "fileutils", "forwardable", "prime", "tracer", "ipaddr", "cmath", "mutex_m", "sync"
    sync_lib gem
  else
  end
end

def sync_lib(repo)
  unless File.directory?("../#{repo}")
    abort "Expected '../#{repo}' (#{File.expand_path("../#{repo}")}) to be a directory, but it wasn't."
  end
  FileUtils.rm_rf(["lib/#{repo}.rb", "lib/#{repo}/*", "test/test_#{repo}.rb"])
  `cp -rf ../#{repo}/lib/* lib`
  tests = if File.directory?("test/#{repo}")
            "test/#{repo}"
          else
            "test/test_#{repo}.rb"
          end
  `cp -rf ../#{repo}/#{tests} test`
  gemspec = if File.directory?("lib/#{repo}")
              "lib/#{repo}/#{repo}.gemspec"
            else
              "lib/#{repo}.gemspec"
            end
  `cp -f ../#{repo}/#{repo}.gemspec #{gemspec}`
end

def update_default_gems(gem)
  author, repository = $repositories[gem.to_sym].split('/')

  unless File.exist?("../../#{author}/#{repository}")
    `mkdir -p ../../#{author}`
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
  sync_default_gems(ARGV[0])
end
