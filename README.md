# CC Precompiler

This is a demo for how to implement a precompiler module with [elixir_make](https://github.com/elixir-lang/elixir_make).

The guide for this demo can be found in the repo of `elixir_make`, in the `PRECOMPILATION_GUIED.md` file.

Triplet for current host will always be available, `:erlang.system_info(:system_architecture)`.

For other triplets, this precompiler will try to detect whether `aarch64-linux-gnu-gcc` and/or `riscv64-linux-gnu-gcc` presents in the system by default. If yes, the corresponding target triplet will be available (`aarch64-linux-gnu` and/or `riscv64-linux-gnu`).

It is possible to overwrite these values in `config/config.exs`. For example,

```elixir
import Config
config :APP_NAME, :cc_precompile, [
  # optional config that forces overwriting the
  #   triplet of current host
  #
  # if `current_target` exists in the `compilers` below,
  # then "CC", "CXX" and "CPP" will be overwritten as well.
  # otherwise, this would only changes the target triplet
  #   for current target, and "CC" will be "gcc", "CXX" and 
  #   "CPP" will be "g++"
  current_target: "ppc64le-linux-gnu",

  # optional config that provides a map of available compilers
  #   in different systems
  #   
  # key is a tuple that is used to match the result of `:os.type`,
  #   this allows us to provide different available targets in
  #   different systems
  # value is a map that describes what compilers are available
  #   key is a string taht denotes the target triplet
  #   value is either a 2-tuple, a 3-tuple or a 4-tuple
  #     - for 2-tuples, the elements are the executable name of
  #       the C and C++ compiler respectively
  #
  #     - for 3-tuples, the first element should be `:script`
  #       the second element is the path to the elixir script file
  #       the third element is a 2-tuple, 
  #          the first one is the name of the module
  #          the second one is custom args
  #       the module need to impl the `CCPrecompiler.CompileScript`
  #       behaviour
  #
  #     - for 4-tuples, the first two elements are the same as in
  #       2-tuple, the third and fourth elements are the extra args
  #       that will be passed to the compiler. 
  #
  # the last entry below shows the example of using zig as the
  #   crosscompiler for `aarch64-linux-musl`, the "CC" will be
  #   "zig cc -target aarch64-linux-musl", and "CXX" and "CPP" will be
  #   "zig c++ -target aarch64-linux-musl"
  compilers: %{
    {:unix, :linux} => %{
      "riscv64-linux-gnu" => {"riscv64-linux-gnu-gcc", "riscv64-linux-gnu-g++"},
      "arm-linux-gnueabihf" => {"gcc-arm-linux-gnueabihf", "g++-arm-linux-gnueabihf"},
      "aarch64-linux-musl" => {
        "zig", "zig", "cc -target aarch64-linux-musl", "c++ -target aarch64-linux-musl"
      }
    },
    {:unix, :darwin} => %{
      "x86_64-apple-darwin" => {
        "gcc", "g++", "-arch x86_64", "-arch x86_64"
      },
      "aarch64-apple-darwin" => {
        "gcc", "g++", "-arch aarch64", "-arch aarch64"
      },
      "aarch64-linux-musl" => {
        "zig", "zig", "cc -target aarch64-linux-musl", "c++ -target aarch64-linux-musl"
      },
      "custom" => {
        :script, "custom.exs", {CustomCompile, []}
      }
    }
  }
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

