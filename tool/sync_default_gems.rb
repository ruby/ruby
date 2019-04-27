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
#

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
  mutex_m: "ruby/mutex_m"
}

def sync_default_gems(gem)
  puts "Sync #{$repositories[gem.to_sym]}"

  case gem
  when "rubygems"
    `rm -rf lib/rubygems* test/rubygems`
    `cp -r ../../rubygems/rubygems/lib/rubygems* ./lib`
    `cp -r ../../rubygems/rubygems/test/rubygems ./test`
  when "bundler"
    `rm -rf lib/bundler* libexec/bundler libexec/bundle spec/bundler man/bundle* man/gemfile*`
    `cp -r ../../bundler/bundler/lib/bundler* ./lib`
    `cp -r ../../bundler/bundler/exe/bundle* ./libexec`
    `cp ../../bundler/bundler/bundler.gemspec ./lib/bundler`
    `cp -r ../../bundler/bundler/spec spec/bundler`
    `cp -r ../../bundler/bundler/man/*.{1,5,1\.txt,5\.txt,ronn} ./man`
    `rm -rf spec/bundler/support/artifice/vcr_cassettes`
  when "rdoc"
    `rm -rf lib/rdoc* test/rdoc libexec/rdoc libexec/ri`
    `cp -rf ../rdoc/lib/rdoc* ./lib`
    `cp -rf ../rdoc/test test/rdoc`
    `cp ../rdoc/rdoc.gemspec ./lib/rdoc`
    `cp -rf ../rdoc/exe/rdoc ./libexec`
    `cp -rf ../rdoc/exe/ri ./libexec`
    `rm -f lib/rdoc/markdown.kpeg lib/rdoc/markdown/literals.kpeg lib/rdoc/rd/block_parser.ry lib/rdoc/rd/inline_parser.ry`
    `git checkout lib/rdoc/.document`
  when "reline"
    `rm -rf lib/reline* test/reline`
    `cp -rf ../reline/lib/reline* ./lib`
    `cp -rf ../reline/test test/reline`
    `cp ../reline/reline.gemspec ./lib/reline`
  when "json"
    `rm -rf ext/json test/json`
    `cp -rf ../../flori/json/ext/json/ext ext/json`
    `cp -rf ../../flori/json/tests test/json`
    `cp -rf ../../flori/json/lib ext/json`
    `rm -rf ext/json/lib/json/pure*`
    `cp ../../flori/json/json.gemspec ext/json`
    `rm -r ext/json/lib/json/ext`
    `git checkout ext/json/extconf.rb ext/json/parser/prereq.mk ext/json/generator/depend ext/json/parser/depend`
  when "psych"
    `rm -rf ext/psych test/psych`
    `cp -rf ../psych/ext/psych ./ext`
    `cp -rf ../psych/lib ./ext/psych`
    `cp -rf ../psych/test/psych ./test`
    `rm -rf ext/psych/lib/org ext/psych/lib/psych.jar ext/psych/lib/psych_jars.rb`
    `rm -rf ext/psych/lib/psych.{bundle,so} ext/psych/lib/{2.0,2.1,2.2,2.3,2.4}`
    `rm -f ext/psych/yaml/LICENSE`
    `cp ../psych/psych.gemspec ext/psych/`
    `git checkout ext/psych/depend`
  when "fiddle"
    `rm -rf ext/fiddle test/fiddle`
    `cp -rf ../fiddle/ext/fiddle ext`
    `cp -rf ../fiddle/lib ext/fiddle`
    `cp -rf ../fiddle/test/fiddle test`
    `cp -f ../fiddle/fiddle.gemspec ext/fiddle`
    `git checkout ext/fiddle/depend`
    `rm -rf ext/fiddle/lib/fiddle.{bundle,so}`
  when "stringio"
    `rm -rf ext/stringio test/stringio`
    `cp -rf ../stringio/ext/stringio ext`
    `cp -rf ../stringio/test/stringio test`
    `cp -f ../stringio/stringio.gemspec ext/stringio`
    `git checkout ext/stringio/depend ext/stringio/README.md`
  when "ioconsole"
    `rm -rf ext/io/console test/io/console`
    `cp -rf ../io-console/ext/io/console ext/io`
    `cp -rf ../io-console/test/io/console test/io`
    `mkdir -p ext/io/console/lib`
    `cp -rf ../io-console/lib/console ext/io/console/lib`
    `cp -f ../io-console/io-console.gemspec ext/io/console`
    `git checkout ext/io/console/depend`
  when "dbm"
    `rm -rf ext/dbm test/dbm`
    `cp -rf ../dbm/ext/dbm ext`
    `cp -rf ../dbm/test/dbm test`
    `cp -f ../dbm/dbm.gemspec ext/dbm`
    `git checkout ext/dbm/depend`
  when "gdbm"
    `rm -rf ext/gdbm test/gdbm`
    `cp -rf ../gdbm/ext/gdbm ext`
    `cp -rf ../gdbm/test/gdbm test`
    `cp -f ../gdbm/gdbm.gemspec ext/gdbm`
    `git checkout ext/gdbm/depend ext/gdbm/README`
  when "sdbm"
    `rm -rf ext/sdbm test/sdbm`
    `cp -rf ../sdbm/ext/sdbm ext`
    `cp -rf ../sdbm/test/sdbm test`
    `cp -f ../sdbm/sdbm.gemspec ext/sdbm`
    `git checkout ext/sdbm/depend`
  when "etc"
    `rm -rf ext/etc test/etc`
    `cp -rf ../etc/ext/etc ext`
    `cp -rf ../etc/test/etc test`
    `cp -f ../etc/etc.gemspec ext/etc`
    `git checkout ext/etc/depend`
  when "date"
    `rm -rf ext/date test/date`
    `cp -rf ../date/ext/date ext`
    `cp -rf ../date/lib ext/date`
    `cp -rf ../date/test/date test`
    `cp -f ../date/date.gemspec ext/date`
    `git checkout ext/date/depend`
    `rm -f ext/date/lib/date_core.bundle`
  when "zlib"
    `rm -rf ext/zlib test/zlib`
    `cp -rf ../zlib/ext/zlib ext`
    `cp -rf ../zlib/test/zlib test`
    `cp -f ../zlib/zlib.gemspec ext/zlib`
    `git checkout ext/zlib/depend`
  when "fcntl"
    `rm -rf ext/fcntl`
    `cp -rf ../fcntl/ext/fcntl ext`
    `cp -f ../fcntl/fcntl.gemspec ext/fcntl`
    `git checkout ext/fcntl/depend`
  when "thwait"
    `rm -rf lib/thwait*`
    `cp -rf ../thwait/lib/* lib`
    `cp -rf ../thwait/thwait.gemspec lib/thwait`
  when "e2mmap"
    `rm -rf lib/e2mmap*`
    `cp -rf ../e2mmap/lib/* lib`
    `cp -rf ../e2mmap/e2mmap.gemspec lib`
  when "strscan"
    `rm -rf ext/strscan test/strscan`
    `cp -rf ../strscan/ext/strscan ext`
    `cp -rf ../strscan/test/strscan test`
    `cp -f ../strscan/strscan.gemspec ext/strscan`
    `rm -f ext/strscan/regenc.h ext/strscan/regint.h`
    `git checkout ext/strscan/depend`
  when "rexml", "rss", "matrix", "irb", "csv", "shell", "logger", "ostruct", "scanf", "webrick", "fileutils", "forwardable", "prime", "tracer", "ipaddr", "cmath", "mutex_m", "sync"
    sync_lib gem
  else
  end
end

def sync_lib(repo)
  unless File.directory?("../#{repo}")
    abort "Expected '../#{repo}' (#{File.expand_path("../#{repo}")}) to be a directory, but it wasn't."
  end
  `rm -rf lib/#{repo}.rb lib/#{repo}/* test/test_#{repo}.rb`
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
