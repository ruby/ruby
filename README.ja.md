# Rubyとは

Rubyはシンプルかつ強力なオブジェクト指向スクリプト言語です． Rubyは純粋なオブジェクト指向言語として設計されているので，
オブジェクト指向プログラミングを手軽に行う事が出来ます．もちろん普通の手続き型のプログラミングも可能です．

Rubyはテキスト処理関係の能力などに優れ，Perlと同じくらい強力です．さらにシンプルな文法と，
例外処理やイテレータなどの機構によって，より分かりやすいプログラミングが出来ます．

## Rubyの特長

*   シンプルな文法
*   普通のオブジェクト指向機能(クラス，メソッドコールなど)
*   特殊なオブジェクト指向機能(Mixin, 特異メソッドなど)
*   演算子オーバーロード
*   例外処理機能
*   イテレータとクロージャ
*   ガーベージコレクタ
*   ダイナミックローディング (アーキテクチャによる)
*   移植性が高い．多くのUnix-like/POSIX互換プラットフォーム上で動くだけでなく，Windows， Mac OS
    X，Haikuなどの上でも動く cf.
    https://bugs.ruby-lang.org/projects/ruby-trunk/wiki/SupportedPlatformsJa


## 入手法

### FTPで

以下の場所においてあります．

ftp://ftp.ruby-lang.org/pub/ruby/

### Subversionで

開発先端のソースコードは次のコマンドで取得できます．

    $ svn co https://svn.ruby-lang.org/repos/ruby/trunk/ ruby

他に開発中のブランチの一覧は次のコマンドで見られます．

    $ svn ls https://svn.ruby-lang.org/repos/ruby/branches/

### Gitで

SubversionのミラーをGitHubに公開しています． 以下のコマンドでリポジトリを取得できます．

    $ git clone git://github.com/ruby/ruby.git

## ホームページ

RubyのホームページのURLは

https://www.ruby-lang.org/

です．

## メーリングリスト

Rubyのメーリングリストがあります．参加希望の方は

mailto:ruby-list-request@ruby-lang.org

まで本文に

    subscribe

と書いて送って下さい．

Ruby開発者向けメーリングリストもあります．こちらではrubyのバグ，将来の仕様拡張など実装上の問題について議論されています． 参加希望の方は

mailto:ruby-dev-request@ruby-lang.org

までruby-listと同様の方法でメールしてください．

Ruby拡張モジュールについて話し合うruby-extメーリングリストと数学関係の話題について話し合うruby-mathメーリングリストと
英語でrubyについて話し合うruby-talkメーリングリストもあります．参加方法はどれも同じです．

## コンパイル・インストール

以下の手順で行ってください．

1.  もし `configure` ファイルが見つからない，もしくは `configure.in` より古いようなら， `autoconf` を実行して
    新しく `configure` を生成する

2.  `configure` を実行して `Makefile` などを生成する

    環境によってはデフォルトのCコンパイラ用オプションが付きます． `configure` オプションで `optflags=..`
    `warnflags=..` 等で上書きできます．

3.  (必要ならば)`defines.h` を編集する

    多分，必要無いと思います．

4.  (必要ならば)`ext/Setup` に静的にリンクする拡張モジュールを指定する

    `ext/Setup` に記述したモジュールは静的にリンクされます．

    ダイナミックローディングをサポートしていないアーキテクチャでは `Setup` の1行目の「`option nodynamic`」という行のコ
    メントを外す必要があります．また，このアーキテクチャで拡張モジュールを利用するためには，あらかじめ静的にリンクをしておく必要があります．

5.  `make` を実行してコンパイルする

6.  `make check`でテストを行う．

    「`check succeeded`」と表示されれば成功です．ただしテストに成功しても完璧だと保証されている訳ではありません．

7.  `make install`

    以下のディレクトリを作って，そこにファイルをインストー ルします．

    *   `${DESTDIR}${prefix}/bin`
    *   `${DESTDIR}${prefix}/include/ruby-${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/include/ruby-${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}`
    *   `${DESTDIR}${prefix}/lib`
    *   `${DESTDIR}${prefix}/lib/ruby`
    *   `${DESTDIR}${prefix}/lib/ruby/${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/lib/ruby/${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}`
    *   `${DESTDIR}${prefix}/lib/ruby/site_ruby`
    *   `${DESTDIR}${prefix}/lib/ruby/site_ruby/${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/lib/ruby/site_ruby/${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}`
    *   `${DESTDIR}${prefix}/lib/ruby/vendor_ruby`
    *   `${DESTDIR}${prefix}/lib/ruby/vendor_ruby/${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/lib/ruby/vendor_ruby/${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}`
    *   `${DESTDIR}${prefix}/lib/ruby/gems/${MAJOR}.${MINOR}.${TEENY}`
    *   `${DESTDIR}${prefix}/share/man/man1`
    *   `${DESTDIR}${prefix}/share/ri/${MAJOR}.${MINOR}.${TEENY}/system`


    RubyのAPIバージョンが'*x.y.z*'であれば，`${MAJOR}`は
    '*x*'で，`${MINOR}`は'*y*'，`${TEENY}`は'*z*'です．

    **注意**: APIバージョンの `teeny` は，Rubyプログラムのバージョンとは異なることがあります．

    `root` で作業する必要があるかもしれません．


もし，コンパイル時にエラーが発生した場合にはエラーのログとマシン，OSの種類を含むできるだけ詳しいレポートを作者に送って下さると他の方のためにもなります．

## 移植

UNIXであれば `configure` がほとんどの差異を吸収してくれるはずですが，思わぬ見落としがあった場合(ある事が多い)，作者にその
ことを報告すれば，解決できる可能性があります．

アーキテクチャにもっとも依存するのはGC部です．RubyのGCは対象
のアーキテクチャが`setjmp()`または`getcontext()`によって全てのレジスタを `jmp_buf` や `ucontext_t`
に格納することと， `jmp_buf` や `ucontext_t` とスタックが32bitアラインメントされていることを仮定
しています．特に前者が成立しない場合の対応は非常に困難でしょう． 後者の解決は比較的簡単で， `gc.c` でスタックをマークしている
部分にアラインメントのバイト数だけずらしてマークするコードを追加するだけで済みます．`defined(__mc68000__)`で括られてい
る部分を参考にしてください．

レジスタウィンドウを持つCPUでは，レジスタウィンドウをスタックにフラッシュするアセンブラコードを追加する必要があるかもしれません．

## 配布条件

[COPYING.ja](COPYING.ja) ファイルを参照してください．

## フィードバック

Rubyに関する質問は Ruby-Talk（英語）や Ruby-List（日本語） (https://www.ruby-lang.org/ja/community/mailing-lists) や，
stackoverflow (https://ja.stackoverflow.com/) などのWebサイトに投稿してください．

バグ報告は https://bugs.ruby-lang.org で受け付けています．


## 著者

Rubyのオリジナル版は，1995年にまつもとゆきひろ氏によって設計・開発されました．

<mailto:matz@ruby-lang.org>

---
created at: Thu Aug  3 11:57:36 JST 1995
