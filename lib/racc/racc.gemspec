# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "racc".freeze
  s.version = "1.4.16.pre.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Aaron Patterson".freeze]
  s.date = "2019-06-20"
  s.description = "Racc is a LALR(1) parser generator.\n  It is written in Ruby itself, and generates Ruby program.\n\n  NOTE: Ruby 1.8.x comes with Racc runtime module.  You\n  can run your parsers generated by racc 1.4.x out of the\n  box.".freeze
  s.email = ["aaron@tenderlovemaking.com".freeze]
  s.executables = ["racc".freeze, "racc2y".freeze, "y2racc".freeze]
  s.extensions = ["ext/racc/extconf.rb".freeze]
  s.extra_rdoc_files = ["Manifest.txt".freeze, "README.ja.rdoc".freeze, "README.rdoc".freeze, "rdoc/en/NEWS.en.rdoc".freeze, "rdoc/en/grammar.en.rdoc".freeze, "rdoc/ja/NEWS.ja.rdoc".freeze, "rdoc/ja/debug.ja.rdoc".freeze, "rdoc/ja/grammar.ja.rdoc".freeze, "rdoc/ja/parser.ja.rdoc".freeze, "README.ja.rdoc".freeze, "README.rdoc".freeze]
  s.files = ["COPYING".freeze, "ChangeLog".freeze, "DEPENDS".freeze, "Manifest.txt".freeze, "README.ja.rdoc".freeze, "README.rdoc".freeze, "Rakefile".freeze, "TODO".freeze, "bin/racc".freeze, "bin/racc2y".freeze, "bin/y2racc".freeze, "ext/racc/MANIFEST".freeze, "ext/racc/com/headius/racc/Cparse.java".freeze, "ext/racc/cparse.c".freeze, "ext/racc/depend".freeze, "ext/racc/extconf.rb".freeze, "fastcache/extconf.rb".freeze, "fastcache/fastcache.c".freeze, "lib/racc.rb".freeze, "lib/racc/compat.rb".freeze, "lib/racc/debugflags.rb".freeze, "lib/racc/exception.rb".freeze, "lib/racc/grammar.rb".freeze, "lib/racc/grammarfileparser.rb".freeze, "lib/racc/info.rb".freeze, "lib/racc/iset.rb".freeze, "lib/racc/logfilegenerator.rb".freeze, "lib/racc/parser-text.rb".freeze, "lib/racc/parser.rb".freeze, "lib/racc/parserfilegenerator.rb".freeze, "lib/racc/pre-setup".freeze, "lib/racc/sourcetext.rb".freeze, "lib/racc/state.rb".freeze, "lib/racc/statetransitiontable.rb".freeze, "lib/racc/static.rb".freeze, "misc/dist.sh".freeze, "rdoc/en/NEWS.en.rdoc".freeze, "rdoc/en/grammar.en.rdoc".freeze, "rdoc/ja/NEWS.ja.rdoc".freeze, "rdoc/ja/command.ja.html".freeze, "rdoc/ja/debug.ja.rdoc".freeze, "rdoc/ja/grammar.ja.rdoc".freeze, "rdoc/ja/index.ja.html".freeze, "rdoc/ja/parser.ja.rdoc".freeze, "rdoc/ja/usage.ja.html".freeze, "sample/array.y".freeze, "sample/array2.y".freeze, "sample/calc-ja.y".freeze, "sample/calc.y".freeze, "sample/conflict.y".freeze, "sample/hash.y".freeze, "sample/lalr.y".freeze, "sample/lists.y".freeze, "sample/syntax.y".freeze, "sample/yyerr.y".freeze, "setup.rb".freeze, "tasks/doc.rb".freeze, "tasks/email.rb".freeze, "test/assets/cadenza.y".freeze, "test/assets/cast.y".freeze, "test/assets/chk.y".freeze, "test/assets/conf.y".freeze, "test/assets/csspool.y".freeze, "test/assets/digraph.y".freeze, "test/assets/echk.y".freeze, "test/assets/edtf.y".freeze, "test/assets/err.y".freeze, "test/assets/error_recovery.y".freeze, "test/assets/expect.y".freeze, "test/assets/firstline.y".freeze, "test/assets/huia.y".freeze, "test/assets/ichk.y".freeze, "test/assets/intp.y".freeze, "test/assets/journey.y".freeze, "test/assets/liquor.y".freeze, "test/assets/machete.y".freeze, "test/assets/macruby.y".freeze, "test/assets/mailp.y".freeze, "test/assets/mediacloth.y".freeze, "test/assets/mof.y".freeze, "test/assets/namae.y".freeze, "test/assets/nasl.y".freeze, "test/assets/newsyn.y".freeze, "test/assets/noend.y".freeze, "test/assets/nokogiri-css.y".freeze, "test/assets/nonass.y".freeze, "test/assets/normal.y".freeze, "test/assets/norule.y".freeze, "test/assets/nullbug1.y".freeze, "test/assets/nullbug2.y".freeze, "test/assets/opal.y".freeze, "test/assets/opt.y".freeze, "test/assets/percent.y".freeze, "test/assets/php_serialization.y".freeze, "test/assets/recv.y".freeze, "test/assets/riml.y".freeze, "test/assets/rrconf.y".freeze, "test/assets/ruby18.y".freeze, "test/assets/ruby19.y".freeze, "test/assets/ruby20.y".freeze, "test/assets/ruby21.y".freeze, "test/assets/ruby22.y".freeze, "test/assets/scan.y".freeze, "test/assets/syntax.y".freeze, "test/assets/tp_plus.y".freeze, "test/assets/twowaysql.y".freeze, "test/assets/unterm.y".freeze, "test/assets/useless.y".freeze, "test/assets/yyerr.y".freeze, "test/bench.y".freeze, "test/helper.rb".freeze, "test/infini.y".freeze, "test/regress/cadenza".freeze, "test/regress/cast".freeze, "test/regress/csspool".freeze, "test/regress/edtf".freeze, "test/regress/huia".freeze, "test/regress/journey".freeze, "test/regress/liquor".freeze, "test/regress/machete".freeze, "test/regress/mediacloth".freeze, "test/regress/mof".freeze, "test/regress/namae".freeze, "test/regress/nasl".freeze, "test/regress/nokogiri-css".freeze, "test/regress/opal".freeze, "test/regress/php_serialization".freeze, "test/regress/riml".freeze, "test/regress/ruby18".freeze, "test/regress/ruby22".freeze, "test/regress/tp_plus".freeze, "test/regress/twowaysql".freeze, "test/scandata/brace".freeze, "test/scandata/gvar".freeze, "test/scandata/normal".freeze, "test/scandata/percent".freeze, "test/scandata/slash".freeze, "test/src.intp".freeze, "test/start.y".freeze, "test/test_chk_y.rb".freeze, "test/test_grammar_file_parser.rb".freeze, "test/test_racc_command.rb".freeze, "test/test_scan_y.rb".freeze, "test/testscanner.rb".freeze, "web/racc.en.rhtml".freeze, "web/racc.ja.rhtml".freeze]
  s.homepage = "http://i.loveruby.net/en/projects/racc/".freeze
  s.licenses = ["MIT".freeze]
  s.rdoc_options = ["--main".freeze, "README.rdoc".freeze]
  s.rubygems_version = "3.1.0.pre1".freeze
  s.summary = "Racc is a LALR(1) parser generator".freeze

  s.add_development_dependency(%q<rake-compiler>.freeze, [">= 0.4.1"])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 4.7"])
  s.add_development_dependency(%q<rdoc>.freeze, [">= 4.0", "< 7"])
  s.add_development_dependency(%q<hoe>.freeze, ["~> 3.18"])
end
