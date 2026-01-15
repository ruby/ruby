# WebAssembly / WASI port of Ruby

## How to cross-build

### Requirement

- Ruby (the same version as the building target version) (baseruby)
- GNU make
- [WASI SDK](https://github.com/WebAssembly/wasi-sdk) 14.0 or later
- [Binaryen](https://github.com/WebAssembly/binaryen) version 106 or later
- Linux or macOS build machine

### Steps

1. Download a prebuilt WASI SDK package from [WASI SDK release page](https://github.com/WebAssembly/wasi-sdk/releases).

2. Set `WASI_SDK_PATH` environment variable to the root directory of the WASI SDK package.

    ```console
    $ export WASI_SDK_PATH=/path/to/wasi-sdk-X.Y
    ```

3. Download a prebuilt binaryen from [Binaryen release page](https://github.com/WebAssembly/binaryen/releases)

4. Set PATH environment variable to lookup binaryen tools

    ```console
    $ export PATH=path/to/binaryen:$PATH
    ```

5. Download the latest `config.guess` with WASI support, and run `./autogen.sh` to generate configure when you are building from the source checked out from Git repository

    ```console
    $ ruby tool/downloader.rb -d tool -e gnu config.guess config.sub
    $ ./autogen.sh
    ```

6. Configure
    - You can select which extensions you want to build.
    - If you got `Out of bounds memory access` while running the produced ruby, you may need to increase the maximum size of stack.

        ```console
        $ ./configure LDFLAGS="-Xlinker -zstack-size=16777216" \
          --host wasm32-unknown-wasi \
          --with-destdir=./ruby-wasm32-wasi \
          --with-static-linked-ext \
          --with-ext=ripper,monitor
        ```

7. Make

    ```console
    $ make install
    ```

Now you have a WASI compatible ruby binary. You can run it by any WebAssembly runtime like [`wasmtime`](https://github.com/bytecodealliance/wasmtime), [`wasmer`](https://github.com/wasmerio/wasmer), [Node.js](https://nodejs.org/api/wasi.html), or browser with [WASI polyfill](https://www.npmjs.com/package/@wasmer/wasi).

Note: it may take a long time (~20 sec) for the first time for JIT compilation

```console
$ wasmtime ruby-wasm32-wasi/usr/local/bin/ruby --mapdir /::./ruby-wasm32-wasi/ -- -e 'puts RUBY_PLATFORM'
wasm32-wasi
```

Note: you cannot run the built ruby without a WebAssembly runtime, because of the difference of the binary file type.

```console
$ ruby-wasm32-wasi/usr/local/bin/ruby -e 'puts "a"'
bash: ruby-wasm32-wasi/usr/local/bin/ruby: cannot execute binary file: Exec format error

$ file ruby-wasm32-wasi/usr/local/bin/ruby
ruby-wasm32-wasi/usr/local/bin/ruby: WebAssembly (wasm) binary module version 0x1 (MVP)
```

## Current Limitation

- No `Thread` support for now.
- Spawning a new process is not supported. e.g. `Kernel.spawn` and `Kernel.system`
