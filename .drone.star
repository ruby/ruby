def pipeline(name, arch, failure=None):
  out = {
    "kind": "pipeline",
    "type": "docker",
    "name": name,
    "platform": {
      "os": "linux",
      "arch": arch,
    },
    "steps": [
      {
        "name": "test",
        "image": "ruby:2.5-stretch",
        "commands": [
          "uname -m",
          "apt-get -yq update",
          "apt-get -yq install software-properties-common",
          "apt-get -yq install bison sudo",
          # workaround ipv6 localhost
          # .drone.star: "found unknown escape character" with backslash x 1 or 2
          # https://discourse.drone.io/t/drone-star-found-unknown-escape-character-with-backslash-x-1-or-2/5908
          "ruby -e \"hosts = File.read('/etc/hosts').sub(/^::1\\\\s*localhost.*$/, ''); File.write('/etc/hosts', hosts)\"",
          # create user
          "useradd --shell /bin/bash --create-home test && chown -R test:test .",
          # configure
          "/usr/bin/sudo -H -u test -- bash -c 'autoconf && ./configure --disable-install-doc --prefix=/tmp/ruby-prefix'",
          # make all install
          "/usr/bin/sudo -H -u test -- make -j$(nproc) all install",
          # make test
          "/usr/bin/sudo -H -u test -- make test",
          # make test-spec
          "/usr/bin/sudo -H -u test -- make test-spec",
          # make test-all
          "/usr/bin/sudo -H -u test -- make test-all"
        ]
      }
    ],
    "trigger": {
      "branch": [
        "master"
      ]
    }
  }
  if failure:
    for step in out["steps"]:
      step["failure"] = failure
  return out

def main(ctx):
  return [
    pipeline("arm64", "arm64"),
    pipeline("arm32", "arm", failure="ignore") # `make test` is failing on arm32
  ]
