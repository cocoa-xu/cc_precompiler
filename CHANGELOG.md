# Changelog

## v0.1.6 (2022-02-20)

### Added
- allow missing CC or CXX when detecting available targets by setting `allow_missing_compiler` to `true`.

  Adding this option because there is no need to require the presence of both CC and CXX for projects that only uses one of them.

  ```elixir
  def project do
    [ 
    # ...
    cc_precompiler: [
        # optional config key
        #   true - the corresponding target will be available as long as we can detect either `CC` or `CXX`
        #   false  - both `CC` and `CXX` should be present on the system
        # defaults to `false`
        allow_missing_compiler: false,
        # ...
    ],
    # ...
    ]
  end
  ```
