#!./miniruby

if RUBY_PATCHLEVEL.zero?
	dirname = sprintf 'ruby-%s', RUBY_VERSION
	tagname = dirname.gsub /ruby-(\d)\.(\d)\.(\d)/, 'v\1_\2_\3'
else
	dirname = sprintf 'ruby-%s-p%u', RUBY_VERSION, RUBY_PATCHLEVEL
	tagname = dirname.gsub /ruby-(\d)\.(\d)\.(\d)-p/, 'v\1_\2_\3_'
end
tgzname = dirname + '.tar.gz'
tbzname = dirname + '.tar.bz2'
zipname = dirname + '.zip'
repos   = 'http://svn.ruby-lang.org/repos/ruby/tags/' + tagname

STDERR.puts 'exporting sources...'
system 'svn',  'export',  '-q', repos, dirname
Dir.chdir dirname do
	STDERR.puts 'generating configure...'
	system 'autoconf'
	system 'rm', '-rf', 'autom4te.cache'

	STDERR.puts 'generating parse.c...'
	system 'bison', '-y', '-o', 'parse.c', 'parse.y'
end

STDERR.puts 'generating tarballs...'
ENV['GZIP'] = '-9'
system 'tar', 'chofzp', tgzname, dirname
system 'tar', 'chojfp', tbzname, dirname
system 'zip', '-q9r', zipname, dirname

require 'digest/md5'
require 'digest/sha2'
for name in [tgzname, tbzname, zipname] do
	open name, 'rb' do |fp|
		str = fp.read
		md5 = Digest::MD5.hexdigest str
		sha = Digest::SHA256.hexdigest str
		printf "MD5(%s)= %s\nSHA256(%s)= %s\nSIZE(%s)= %s\n\n",
				 name, md5,
				 name, sha,
				 name, str.size
	end
end



# 
# Local Variables:
# mode: ruby
# code: utf-8
# indent-tabs-mode: t
# tab-width: 3
# ruby-indent-level: 3
# fill-column: 79
# default-justification: full
# End:
# vi: ts=3 sw=3

