defmodule CCPrecompiler.CompileScript do
  @callback compile(
              app :: atom(),
              version :: String.t(),
              nif_version :: String.t(),
              cache_dir :: String.t(),
              command_line_args :: [String.t()],
              custom_args :: [String.t()]
            ) ::
              {
                archive_full_path :: String.t(),
                archive_tar_gz :: String.t(),
                checksum_algo :: :sha256,
                checksum :: String.t()
              }
end

defmodule CCPrecompiler do
  @moduledoc """
  Precompile with existing crosscompiler in the system.
  """

  require Logger
  @behaviour ElixirMake.Precompiler

  # this is the default configuration for this demo precompiler module
  # for linux systems, it will detect for the following targets
  #   - aarch64-linux-gnu
  #   - riscv64-linux-gnu
  #   - arm-linux-gnueabihf
  # by trying to find the corresponding executable, i.e.,
  #   - aarch64-linux-gnu-gcc
  #   - riscv64-linux-gnu-gcc
  #   - gcc-arm-linux-gnueabihf
  # (this demo module will only try to find the CC executable, a step further
  # will be trying to compile a simple C/C++ program using them)
  @default_compilers %{
    {:unix, :linux} => %{
      "aarch64-linux-gnu" => {"aarch64-linux-gnu-gcc", "aarch64-linux-gnu-g++"},
      "riscv64-linux-gnu" => {"riscv64-linux-gnu-gcc", "riscv64-linux-gnu-g++"},
      "arm-linux-gnueabihf" => {"gcc-arm-linux-gnueabihf", "g++-arm-linux-gnueabihf"}
    },
    {:unix, :darwin} => %{
      "x86_64-apple-darwin" => {
        "gcc",
        "g++",
        "<%= cc %> -arch x86_64",
        "<%= cxx %> -arch x86_64"
      },
      "aarch64-apple-darwin" => {
        "gcc",
        "g++",
        "<%= cc %> -arch arm64",
        "<%= cxx %> -arch arm64"
      }
    }
  }
  @user_config Application.compile_env(Mix.Project.config()[:app], :cc_precompile)
  @compilers Access.get(@user_config, :compilers, @default_compilers)
  @compilers_current_os Access.get(@compilers, :os.type(), %{})
  @impl ElixirMake.Precompiler
  def current_target do
    current_target_user_overwrite = Access.get(@user_config, :current_target)

    if current_target_user_overwrite do
      # overwrite current target triplet
      {:ok, current_target_user_overwrite}
    else
      # get current target triplet from `:erlang.system_info/1`
      system_architecture = to_string(:erlang.system_info(:system_architecture))
      current = String.split(system_architecture, "-", trim: true)

      case length(current) do
        4 ->
          {:ok, "#{Enum.at(current, 0)}-#{Enum.at(current, 2)}-#{Enum.at(current, 3)}"}

        3 ->
          case :os.type() do
            {:unix, :darwin} ->
              # could be something like aarch64-apple-darwin21.0.0
              # but we don't really need the last 21.0.0 part
              if String.match?(Enum.at(current, 2), ~r/^darwin.*/) do
                {:ok, "#{Enum.at(current, 0)}-#{Enum.at(current, 1)}-darwin"}
              else
                {:ok, system_architecture}
              end

            _ ->
              {:ok, system_architecture}
          end

        _ ->
          {:error, "cannot decide current target"}
      end
    end
  end

  @impl ElixirMake.Precompiler
  def all_supported_targets(:compile) do
    # this callback is expected to return a list of string for
    #   all supported targets by this precompiler. in this
    #   implementation, we will try to find a few crosscompilers
    #   available in the system.
    # Note that this implementation is mainly used for demostration
    #   purpose, therefore the hardcoded compiler names are used in
    #   DEBIAN/Ubuntu Linux (as I only installed these ones at the
    #   time of writting this example)
    with {:ok, current} <- current_target() do
      Enum.uniq([current] ++ find_all_available_targets())
    else
      _ ->
        []
    end
  end

  @impl ElixirMake.Precompiler
  def all_supported_targets(:fetch) do
    List.flatten(Enum.map(@compilers, &Map.keys(elem(&1, 1))))
  end

  defp find_all_available_targets do
    @compilers_current_os
    |> Map.keys()
    |> Enum.map(&find_available_compilers(&1, Map.get(@compilers_current_os, &1)))
    |> Enum.reject(fn x -> x == nil end)
  end

  defp find_available_compilers(triplet, compilers) when is_tuple(compilers) do
    if System.find_executable(elem(compilers, 0)) do
      Logger.debug("Found compiler for #{triplet}")
      triplet
    else
      Logger.debug("Compiler not found for #{triplet}")
      nil
    end
  end

  defp find_available_compilers(triplet, invalid) do
    Mix.raise(
      "Invalid configuration for #{triplet}, expecting a 2-tuple or 4-tuple, however, got #{inspect(invalid)}"
    )
  end

  @impl ElixirMake.Precompiler
  def build_native(args) do
    # in this callback we just build the NIF library natively,
    #   and because this precompiler module is designed for NIF
    #   libraries that use C/C++ as the main language with Makefile,
    #   we can just call `ElixirMake.Compile.compile(args)`
    #
    # it's also possible to forward this call to:
    #
    #   `precompile(args, elem(current_target(), 1))`
    #
    #   this could be useful when the precompiler is using a universal
    #   (cross-)compiler, say zig. in this way, the compiled binaries
    #   (`mix compile`) will be consistent as the corrsponding precompiled
    #   one (with `mix elixir_make.precompile`)
    #
    #   however, if you'd prefer to having the same behaviour for `mix compile`
    #   then the following line is okay
    ElixirMake.Compile.compile(args)
  end

  @impl ElixirMake.Precompiler
  def cache_dir() do
    # in this optional callback we can return a custom cache directory
    #   for this precompiler module, this can be useful
    #   - if you'd prefer to save artefacts in some global location
    #   - if you'd like to having a user customisable option such as
    #     `cc_precompiler_cache_dir`
    ElixirMake.Artefact.cache_dir()
  end

  @impl ElixirMake.Precompiler
  def precompile(args, target) do
    # in this callback we compile the NIF library for a given target
    saved_cwd = File.cwd!()
    app = Mix.Project.config()[:app]
    version = Mix.Project.config()[:version]
    nif_version = ElixirMake.Compile.current_nif_version()

    saved_cc = System.get_env("CC") || ""
    saved_cxx = System.get_env("CXX") || ""
    saved_cpp = System.get_env("CPP") || ""

    Logger.debug("Current compiling target: #{target}")
    ElixirMake.Artefact.make_priv_dir(app, :clean)

    case get_cc_and_cxx(target) do
      {cc, cxx} ->
        System.put_env("CC", cc)
        System.put_env("CXX", cxx)
        System.put_env("CPP", cxx)

        ElixirMake.Compile.compile(args)

      {:script, module, custom_args} ->
        Kernel.apply(module, :compile, [
          app,
          version,
          nif_version,
          target,
          cache_dir(),
          args,
          custom_args
        ])
    end

    File.cd!(saved_cwd)
    System.put_env("CC", saved_cc)
    System.put_env("CXX", saved_cxx)
    System.put_env("CPP", saved_cpp)

    :ok
  end

  defp get_cc_and_cxx(triplet, default \\ {"gcc", "g++"}) do
    case Access.get(@compilers_current_os, triplet, default) do
      {cc, cxx} ->
        {cc, cxx}

      {:script, script_path, {module, args}} ->
        Code.require_file(script_path)
        {:script, module, args}

      {cc, cxx, cc_args, cxx_args} ->
        {EEx.eval_string(cc_args, cc: cc), EEx.eval_string(cxx_args, cxx: cxx)}
    end
  end

  @impl ElixirMake.Precompiler
  def post_precompile() do
    Logger.debug("Post precompile")
    write_metadata_to_file()
  end

  defp write_metadata_to_file() do
    app = Mix.Project.config()[:app]
    version = Mix.Project.config()[:version]
    nif_version = ElixirMake.Compile.current_nif_version()
    cache_dir = ElixirMake.Artefact.cache_dir()

    with {:ok, target} <- current_target() do
      archived_artefact_file =
        ElixirMake.Artefact.archive_filename(app, version, nif_version, target)

      metadata = %{
        app: app,
        cached_tar_gz: Path.join([cache_dir, archived_artefact_file]),
        target: target,
        targets: all_supported_targets(:fetch),
        version: version
      }

      ElixirMake.Artefact.write_metadata(app, metadata)
    end

    :ok
  end
end
