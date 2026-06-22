# ostruct will be loaded when JSON::GenericObject is autoloaded.  By
# removing all test methods, the autoload in `setup` is not triggered.

exclude /test_/, 'JSON::GenericObject needs ostruct gem'
