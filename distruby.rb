#!./miniruby

if RUBY_PATCHLEVEL.zero?
	dirname = sprintf 'ruby-%s', RUBY_VERSION
	tagname = dirname.gsub /ruby-(\d)\.(\d)\.(\d)/, 'v\1_\2_\3'
else
	dirname = sprintf 'ruby-%s-p%u', RUBY_VERSION, RUBY_PATCHLEVEL
	tagname = dirname.gsub /ruby-(\d)\.(\d)\.(\d)-p/, 'v\1_\2_\3_'
end
tarname = dirname + '.tar.gz'
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

STDERR.puts 'generating tarball...'
system 'tar', 'chofzp', tarname, dirname

open tarname, 'rb' do |fp|
	require 'digest/md5'
	require 'digest/sha1'
	str = fp.read
	md5 = Digest::MD5.hexdigest str
	sha = Digest::SHA1.hexdigest str
	printf "MD5(%s)= %s\nSHA1(%s)= %s\n", tarname, md5, tarname, sha
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

