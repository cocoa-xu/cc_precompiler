# CC Precompiler

C/C++ Cross-compiler Precompiler is a library that supports [elixir_make](https://github.com/elixir-lang/elixir_make)'s precompilation feature. It's customisble and easy to extend.

The guide for how to `:ccprecompiler` can be found in the `PRECOMPILATION_GUIED.md` file.

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

## Default Targets

By default, it will probe some well-known C/C++ crosss-compilers existing on your system:

#### Linux

  | Target Triplet          | Compiler Prefix, `prefix` | `CC`            | `CXX`           |
  |:------------------------|:--------------------------|:----------------|:----------------|
  | `x86_64-linux-gnu`      | `x86_64-linux-gnu-`       | `#{prefix}-gcc` | `#{prefix}-g++` |
  | `i686-linux-gnu`        | `i686-linux-gnu-`         | `#{prefix}-gcc` | `#{prefix}-g++` |
  | `aarch64-linux-gnu`     | `aarch64-linux-gnu-`      | `#{prefix}-gcc` | `#{prefix}-g++` |
  | `armv7l-linux-gnuabihf` | `arm-linux-gnueabihf-`    | `#{prefix}-gcc` | `#{prefix}-g++` |
  | `riscv64-linux-gnu`     | `riscv64-linux-gnu-`      | `#{prefix}-gcc` | `#{prefix}-g++` |
  | `powerpc64le-linux-gnu` | `powerpc64le-linux-gnu-`  | `#{prefix}-gcc` | `#{prefix}-g++` |
  | `s390x-linux-gnu`       | `s390x-linux-gnu-`        | `#{prefix}-gcc` | `#{prefix}-g++` |

  `cc_precompiler` will try to find `#{prefix}-gcc` in `$PATH`, and if `#{prefix}-gcc` can be found, then the correspondong target will be activiated. Otherwise, that target will be ignored.

#### macOS

  | Target Triplet          | Compiler Prefix, `prefix` | `CC`               | `CXX`              |
  |:------------------------|:--------------------------|:-------------------|:-------------------|
  | `x86_64-apple-darwin`   | N/A                       | `gcc -arch x86_64` | `g++ -arch x86_64` |
  | `aarch64-apple-darwin`  | N/A                       | `gcc -arch arm64`  | `g++ -arch arm64`  |

  `cc_precompiler` will try to find `gcc` in `$PATH`, and if `gcc` can be found, then both `x86_64` and `arm64` target will be activiated. Otherwise, both targets will be ignored.

#### Note
Triplet for current host will be always available, `:erlang.system_info(:system_architecture)`.

For macOS targets, the version part will be trimmed, e.g., `x86_64-apple-darwin21.6.0` will be `x86_64-apple-darwin`.

### Customise Precompilation Targets

To override the default configuration, please set the `cc_precompile` key in `project`. For example,

```elixir

def project do
[ 
  # ...
  cc_precompile: [
    # optional config that provides a map of available compilers
    # on different systems
    compilers: %{
      # key (`:os.type()`)
      #   this allows us to provide different available targets 
      #   on different systems
      # value is a map that describes which compilers are available
      #
      # key == {:unix, :linux} => when compiling on Linux
      {:unix, :linux} => %{
        # key (target triplet) => `riscv64-linux-gnu`
        # value => `{CC, CXX}`
        #   - for 2-tuples, the elements are the executable name of
        #         the C and C++ compiler respectively
        "riscv64-linux-gnu" => {
          "riscv64-linux-gnu-gcc", 
          "riscv64-linux-gnu-g++"
        },
        # key (target triplet) => `armv7l-linux-gnueabihf`
        # value => `{CC, CXX}`
        "armv7l-linux-gnueabihf" => {
          "arm-linux-gnueabihf-gcc",
          "arm-linux-gnueabihf-g++"
        },
        # key (target triplet) => `armv7l-linux-gnueabihf`
        # value => `{CC_EXECUTABLE, CXX_EXECUTABLE, CC_TEMPLATE, CXX_TEMPLATE}`
        #
        # - for 4-tuples, the first two elements are the same as in
        #       2-tuple, the third and fourth elements are the template
        #       string for CC and CPP/CXX. for example,
        #       
        #       the last entry below shows the example of using zig as the
        #       crosscompiler for `aarch64-linux-musl`, 
        #       the "CC" will be
        #           "zig cc -target aarch64-linux-musl", 
        #       and "CXX" and "CPP" will be
        #           "zig c++ -target aarch64-linux-musl"
        "aarch64-linux-musl" => {
          "zig", 
          "zig", 
          "<% cc %> cc -target aarch64-linux-musl", 
          "<% cxx %> c++ -target aarch64-linux-musl"
        }
      },
      # key == {:unix, :darwin} => when compiling on macOS
      {:unix, :darwin} => %{
        # key (target triplet) => `aarch64-apple-darwin`
        # value => `{CC, CXX}`
        "aarch64-apple-darwin" => {
          "gcc -arch arm64", "g++ -arch arm64"
        },
        # key (target triplet) => `aarch64-linux-musl`
        # value => `{CC_EXECUTABLE, CXX_EXECUTABLE, CC_TEMPLATE, CXX_TEMPLATE}`
        "aarch64-linux-musl" => {
          "zig",
          "zig",
          "<% cc %> cc -target aarch64-linux-musl",
          "<% cxx %> c++ -target aarch64-linux-musl"
        },
        # key (target triplet) => `my-custom-target`
        # - for 3-tuples, the first element should be `:script`
        #       the second element is the path to the elixir script file
        #       the third element is a 2-tuple, 
        #          the first one is the name of the module
        #          the second one is custom args
        #       the module need to impl the `compile/5` callback declared in 
        #          `CCPrecompiler.CompileScript`
        "my-custom-target" => {
          :script, "custom.exs", {CustomCompile, []}
        }
      }
    }
  ]
]
```

`CCPrecompiler.CompileScript` is defined as follows,

```elixir
defmodule CCPrecompiler.CompileScript do
  @callback compile(
              app :: atom(),
              version :: String.t(),
              nif_version :: String.t(),
              command_line_args :: [String.t()],
              custom_args :: [String.t()]
            ) :: :ok | {:error, String.t()}
end
```

And a simple custom compile script for reference,

```elixir
defmodule CustomCompileWithCCache do
  @moduledoc """
  Compile with ccache

  ## Example

    "x86_64-linux-gnu" => {
      :script, "custom.exs", {CustomCompileWithCCache, []}
    }
  
  It's also possible to do this using a 4-tuple:

    "x86_64-linux-musl" => {
      "gcc", "g++", "ccache <% cc %>", "ccache <% cxx %>"
    }

  """

  @behaviour CCPrecompiler.CompileScript

  @impl CCPrecompiler.CompileScript
  def compile(app, version, nif_version, target, cache_dir, args, _custom_args) do
    System.put_env("CC", "ccache gcc")
    System.put_env("CXX", "ccache g++")
    System.put_env("CPP", "ccache g++")

    ElixirMake.Precompiler.mix_compile(args)
  end
end
```
