# CC Precompiler

This is a demo for how to implement a precompiler module with [elixir_make](https://github.com/elixir-lang/elixir_make).

The guide for this demo can be found in the repo of `elixir_make`, in the `PRECOMPILATION_GUIED.md` file.

Triplet for current host will always be available, `:erlang.system_info(:system_architecture)`.

For other triplets, this precompiler will try to detect whether `aarch64-linux-gnu-gcc` and/or `riscv64-linux-gnu-gcc` presents in the system by default. If yes, the corresponding target triplet will be available (`aarch64-linux-gnu` and/or `riscv64-linux-gnu`).

It is possible to overwrite these values in `config/config.exs`. For example,

```elixir
import Config
config :cc_precompiler, :config, [
  # optional config that forces overwriting the
  #   triplet of current host
  current_target: "ppc64le-linux-gnu",
  # optional config that provides a list of compiler
  #   executable names and triplets
  compilers: [
    # the first element of the tuple is the
    #   executable name of the compiler
    # the second element is the corresponing 
    #   target triplet
    {"s390x-linux-gnu-gcc", "s390x-linux-gnu"},
    {"gcc-arm-linux-gnueabihf", "arm-linux-gnueabihf"}
  ]
]
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `cc_precompiler` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:cc_precompiler, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/cc_precompiler>.

