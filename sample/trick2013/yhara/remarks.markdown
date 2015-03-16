### Remarks

引数なしで普通に実行してください。

    ruby entry.rb

以下の実装・プラットフォームで動作確認しています。

* ruby 2.0.0p0 (2013-02-24 revision 39474) [x86\_64-darwin12.2.1]

### Description

JUST ANOTHER RUBY HACKERと表示します。

### Internals

Objectクラスの定数から文字を拾っています。
そのために、意図的に例外を起こしています。
「U」が一つしか見つからなかったので、もう一個はRUBY\_COPYRIGHTの
「Yukihiro Matsumoto」から取っています。

### Limitation

JRubyはreturnがエラーにならなくて、動きませんでした。
