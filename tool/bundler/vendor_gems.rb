# frozen_string_literal: true

source "https://rubygems.org"

<<<<<<< HEAD
gem "fileutils", "1.7.3"
gem "molinillo", github: "cocoapods/molinillo"
<<<<<<< HEAD
gem "net-http", github: "ruby/net-http", ref: "d8fd39c589279b1aaec85a7c8de9b3e199c72efe"
gem "net-http-persistent", github: "hsbt/net-http-persistent", ref: "9b6fbd733cf35596dfe7f80c0c154f9f3d17dbdb"
=======
gem "net-http", "0.8.0"
=======
gem "fileutils", "1.8.0"
gem "molinillo", github: "cocoapods/molinillo", ref: "1d62d7d5f448e79418716dc779a4909509ccda2a"
gem "net-http", "0.7.0" # net-http-0.8.0 is broken with JRuby
>>>>>>> 198b10c12d6 (Downgrade net-http 0.7.0 because JRuby is not working)
gem "net-http-persistent", "4.0.6"
>>>>>>> 7e6ce7be57a (Use released version of net-http-0.8.0)
gem "net-protocol", "0.2.2"
gem "optparse", "0.6.0"
gem "pub_grub", github: "jhawthorn/pub_grub", ref: "df6add45d1b4d122daff2f959c9bd1ca93d14261"
gem "resolv", "0.6.2"
gem "securerandom", "0.4.1"
gem "timeout", "0.4.3"
gem "thor", "1.4.0"
gem "tsort", "0.2.0"
gem "uri", "1.0.4"
