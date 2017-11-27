# sync following repositories to ruby repository
#
# * https://github.com/rubygems/rubygems
# * https://github.com/bundler/bundler
# * https://github.com/ruby/rdoc
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
#

$repositories = {
  rubygems: 'rubygems/rubygems',
  bundler: 'bundler/bundler',
  rdoc: 'ruby/rdoc',
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
}

def sync_default_gems(gem)
  author, repository = $repositories[gem.to_sym].split('/')
  unless File.exist?("../../#{author}/#{repository}")
    `mkdir -p ../../#{author}`
    `git clone git@github.com:#{author}/#{repository}.git ../../#{author}/#{repository}`
  end

  puts "Sync #{$repositories[gem.to_sym]}"

  case gem
  when "rubygems"
    `rm -rf lib/rubygems* test/rubygems`
    `cp -r ../../rubygems/rubygems/lib/rubygems* ./lib`
    `cp -r ../../rubygems/rubygems/test/rubygems ./test`
  when "bundler"
    `rm -rf lib/bundler* bin/bundler bin/bundle bin/bundle_ruby spec/bundler`
    `cp -r ../../bundler/bundler/lib/bundler* ./lib`
    `cp -r ../../bundler/bundler/exe/bundle* ./bin`
    `cp ../../bundler/bundler/bundler.gemspec ./lib`
    `cp -r ../../bundler/bundler/spec spec/bundler`
    `rm -rf bin/bundle_ruby`
  when "rdoc"
    `rm -rf lib/rdoc* test/rdoc`
    `cp -rf ../rdoc/lib/rdoc* ./lib`
    `cp -rf ../rdoc/test test/rdoc`
    `cp ../rdoc/rdoc.gemspec ./lib/rdoc`
    `rm -f lib/rdoc/markdown.kpeg lib/rdoc/markdown/literals.kpeg lib/rdoc/rd/block_parser.ry lib/rdoc/rd/inline_parser.ry`
    `git checkout lib/rdoc/.document`
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
  when "fileutils"
    `rm -rf lib/fileutils.rb test/fileutils lib/fileutils.gemspec`
    `cp -rf ../fileutils/lib/* lib`
    `cp -rf ../fileutils/test/fileutils test`
    `cp -f ../fileutils/fileutils.gemspec lib`
  when "fiddle"
    `rm -rf ext/fiddle test/fiddle`
    `cp -rf ../fiddle/ext/fiddle ext`
    `cp -rf ../fiddle/lib ext/fiddle`
    `cp -rf ../fiddle/test/fiddle test`
    `cp -f ../fiddle/fiddle.gemspec ext/fiddle`
    `git checkout ext/fiddle/depend`
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
  when "csv"
    `rm -rf lib/csv.rb test/csv lib/csv.gemspec`
    `cp -rf ../csv/lib/* lib`
    `cp -rf ../csv/test/csv test`
    `cp -f ../csv/csv.gemspec lib`
  when "webrick"
    `rm -rf lib/webrick test/webrick`
    `cp -rf ../webrick/lib/webrick lib`
    `cp -rf ../webrick/test/webrick test`
    `cp -f ../webrick/webrick.gemspec lib/webrick`
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
  when "scanf"
    `rm -rf lib/scanf.rb test/scanf`
    `cp -rf ../scanf/lib/* lib`
    `cp -rf ../scanf/test/scanf test`
    `cp -f ../scanf/scanf.gemspec lib`
  when "cmath"
    `rm -rf lib/cmath.rb test/test_cmath.rb`
    `cp -rf ../cmath/lib/* lib`
    `cp -rf ../cmath/test/test_cmath.rb test`
    `cp -f ../cmath/cmath.gemspec lib`
  when "strscan"
    `rm -rf ext/strscan test/strscan`
    `cp -rf ../strscan/ext/strscan ext`
    `cp -rf ../strscan/test/strscan test`
    `cp -f ../strscan/strscan.gemspec ext/strscan`
    `rm -f ext/strscan/regenc.h ext/strscan/regint.h`
    `git checkout ext/strscan/depend`
  when "ipaddr"
    `rm -rf lib/ipaddr.rb test/test_ipaddr.rb`
    `cp -rf ../ipaddr/lib/* lib`
    `cp -rf ../ipaddr/test/test_ipaddr.rb test`
    `cp -f ../ipaddr/ipaddr.gemspec lib`
  else
  end
end

if ARGV[0]
  sync_default_gems(ARGV[0])
else
  $repositories.keys.each{|gem| sync_default_gems(gem.to_s)}
end
