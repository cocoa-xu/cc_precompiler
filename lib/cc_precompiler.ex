defmodule CCPrecompiler.CompileScript do
  @callback compile(
    app :: atom(),
    version :: String.t(),
    nif_version :: String.t(),
    cache_dir :: String.t(),
    command_line_args :: [String.t()],
    custom_args :: [String.t()]) ::
    {
      archive_full_path :: String.t(),
      archive_tar_gz :: String.t(),
      checksum_algo :: :sha256,
      checksum :: String.t()
    }
end

defmodule Mix.Tasks.ElixirMake.CCPrecompiler do
  @moduledoc """
  Precompile with existing crosscompiler in the system.
  """

  require Logger
  use Mix.Tasks.ElixirMake.Precompile

  @available_nif_versions ~w(2.16)

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
      "arm-linux-gnueabihf" => {"gcc-arm-linux-gnueabihf", "g++-arm-linux-gnueabihf"},
    },
    {:unix, :darwin} => %{
      "x86_64-apple-darwin" => {
        "gcc", "g++", "-arch x86_64", "-arch x86_64"
      },
      "aarch64-apple-darwin" => {
        "gcc", "g++", "-arch arm64", "-arch arm64"
      }
    }
  }
  @user_config Application.compile_env(Mix.Project.config[:app], :cc_precompile)
  @compilers Access.get(@user_config, :compilers, @default_compilers)
  @compilers_current_os Access.get(@compilers, :os.type(), %{})
  @impl Mix.Tasks.ElixirMake.Precompile
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

  @impl Mix.Tasks.ElixirMake.Precompile
  def all_supported_targets() do
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
    Mix.raise("Invalid configuration for #{triplet}, expecting a 2-tuple or 4-tuple, however, got #{inspect(invalid)}")
  end

  @impl Mix.Tasks.ElixirMake.Precompile
  def build_native(args) do
    # in this callback we just build the NIF library natively,
    #   and because this precompiler module is designed for NIF
    #   libraries that use C/C++ as the main language with Makefile,
    #   we can just call `ElixirMake.Compile.compile(args)`
    ElixirMake.Compile.compile(args)
  end

  @impl Mix.Tasks.ElixirMake.Precompile
  def precompile(args, targets) do
    # in this callback we compile the NIF library for each target given
    #   in the list `targets`
    # it's worth noting that the targets in the list could be a subset
    #   of all supported targets because it's possible that `elixir_make`
    #   would allow user to set a filter to keep targets they want in the
    #   future.
    saved_cwd = File.cwd!()
    cache_dir = ElixirMake.Artefact.cache_dir()

    app = Mix.Project.config()[:app]
    version = Mix.Project.config()[:version]
    nif_version = ElixirMake.Compile.current_nif_version()

    precompiled_artefacts =
      do_precompile(app, version, nif_version, args, targets, saved_cwd, cache_dir)

    with {:ok, target} <- current_target() do
      tar_filename = ElixirMake.Artefact.archive_filename(app, version, nif_version, target)
      cached_tar_gz = Path.join([cache_dir, tar_filename])
      ElixirMake.Artefact.restore_nif_file(cached_tar_gz, app)
    end

    Mix.Project.build_structure()
    {:ok, precompiled_artefacts}
  end

  defp get_cc_and_cxx(triplet, default \\ {"gcc", "g++"}) do
    case Access.get(@compilers_current_os, triplet, default) do
      {cc, cxx} ->
        {cc, cxx}
      {:script, script_path, {module, args}} ->
        Code.require_file(script_path)
        {:script, module, args}
      {cc, cxx, cc_args, cxx_args} ->
        {"#{cc} #{cc_args}", "#{cxx} #{cxx_args}"}
    end
  end

  defp do_precompile(app, version, nif_version, args, targets, saved_cwd, cache_dir) do
    saved_cc = System.get_env("CC") || ""
    saved_cxx = System.get_env("CXX") || ""
    saved_cpp = System.get_env("CPP") || ""

    precompiled_artefacts =
      Enum.reduce(targets, [], fn target, checksums ->
        Logger.debug("Current compiling target: #{target}")
        ElixirMake.Artefact.make_priv_dir(app, :clean)

        {_archive_full_path, archive_tar_gz, checksum_algo, checksum} =
          case get_cc_and_cxx(target) do
            {cc, cxx} ->
              System.put_env("CC", cc)
              System.put_env("CXX", cxx)
              System.put_env("CPP", cxx)

              ElixirMake.Compile.compile(args)

              ElixirMake.Artefact.create_precompiled_archive(
                  app,
                  version,
                  nif_version,
                  target,
                  cache_dir
                )
            {:script, module, custom_args} ->
              Kernel.apply(module, :compile, [app, version, nif_version, target, cache_dir, args, custom_args])
          end

        [
          {target, %{path: archive_tar_gz, checksum_algo: checksum_algo, checksum: checksum}}
          | checksums
        ]
      end)
    ElixirMake.Artefact.write_checksum!(app, precompiled_artefacts)

    File.cd!(saved_cwd)
    System.put_env("CC", saved_cc)
    System.put_env("CXX", saved_cxx)
    System.put_env("CPP", saved_cpp)
    precompiled_artefacts
  end

  @impl Mix.Tasks.ElixirMake.Precompile
  def available_nif_urls() do
    # in the callback we return the URL of the precompiled artefacts for all
    #   available targets
    # this implementation will return all URLs regardless if they are reachable
    #   or not. it is possible to only return the URLs that are reachable.
    app = Mix.Project.config()[:app]
    version = Mix.Project.config()[:version]
    base_url = Mix.Project.config()[:cc_precompile_base_url]
    targets = Enum.uniq(List.flatten(Enum.map(Map.values(@compilers), &Map.keys(&1))))

    for target_triple <- targets, nif_version <- @available_nif_versions do
      archive_filename =
        ElixirMake.Artefact.archive_filename(app, version, nif_version, target_triple)

      ElixirMake.Artefact.archive_file_url(base_url, archive_filename)
    end
  end

  @impl Mix.Tasks.ElixirMake.Precompile
  def current_target_nif_url do
    # in the callback we return the URL of the precompiled artefacts for the
    #   current target
    app = Mix.Project.config()[:app]
    metadata = ElixirMake.Artefact.metadata(app)
    nif_version = ElixirMake.Compile.current_nif_version()

    case metadata do
      %{base_url: base_url, target: target, version: version} ->
        archive_filename = ElixirMake.Artefact.archive_filename(app, version, nif_version, target)
        ElixirMake.Artefact.archive_file_url(base_url, archive_filename)

      _ ->
        raise "metadata about current target for the app #{inspect(app)} is not available. " <>
                "Please compile the project again with: `mix FennecPrecompile.precompile`"
    end
  end

  @impl Mix.Tasks.ElixirMake.Precompile
  def precompiler_context(args) do
    # in this optional callback the precompiler module can
    #   return a term with necessary information to be used in
    #     - download_or_reuse_nif_file/1
    #     - post_precompile/1
    # here we just return some random thing for demostration
    %{random_thing: 42, args: args}
  end

  @impl Mix.Tasks.ElixirMake.Precompile
  def post_precompile(context) do
    Logger.debug("Post precompile, context: #{inspect(context)}")
    write_metadata_to_file()
  end

  @impl Mix.Tasks.ElixirMake.Precompile
  def download_or_reuse_nif_file(context) do
    Logger.debug("Download/Reuse, context: #{inspect(context)}")
    cache_dir = ElixirMake.Artefact.cache_dir()

    with {:ok, target} <- current_target() do
      app = Mix.Project.config()[:app]
      version = Mix.Project.config()[:version]
      nif_version = ElixirMake.Compile.current_nif_version()

      # note that `:cc_precompile_base_url` here is the key specific to
      #   this CCPrecompile demo, it's not required by the elixir_make.
      # you can use any name you want for your own precompiler
      base_url = Mix.Project.config()[:cc_precompile_base_url]

      tar_filename = ElixirMake.Artefact.archive_filename(app, version, nif_version, target)

      app_priv = ElixirMake.Artefact.app_priv(app)
      cached_tar_gz = Path.join([cache_dir, tar_filename])

      if !File.exists?(cached_tar_gz) do
        with :ok <- File.mkdir_p(cache_dir),
             {:ok, tar_gz} <-
               ElixirMake.Artefact.download_archived_artefact(base_url, tar_filename),
             :ok <- File.write(cached_tar_gz, tar_gz) do
          Logger.debug("NIF cached at #{cached_tar_gz} and extracted to #{app_priv}")
        end
      end

      with {:file_exists, true} <- {:file_exists, File.exists?(cached_tar_gz)},
          {:file_integrity, :ok} <-
            {:file_integrity, ElixirMake.Artefact.check_file_integrity(cached_tar_gz, app)},
          {:restore_nif, :ok} <-
            {:restore_nif, ElixirMake.Artefact.restore_nif_file(cached_tar_gz, app)} do
        :ok
      else
        # of course you can choose to build from scratch instead of letting elixir_make
        # to raise an error
        {:file_exists, false} ->
          {:error, "Cache file not exists or cannot download"}

        {:file_integrity, _} ->
          {:error, "Cache file integrity check failed"}

        {:restore_nif, status} ->
          {:error, "Cannot restore nif from cache: #{inspect(status)}"}
      end
    end
  end

  defp write_metadata_to_file() do
    app = Mix.Project.config()[:app]
    version = Mix.Project.config()[:version]
    nif_version = ElixirMake.Compile.current_nif_version()
    base_url = Mix.Project.config()[:cc_precompile_base_url]
    cache_dir = ElixirMake.Artefact.cache_dir()

    with {:ok, target} <- current_target() do
      archived_artefact_file =
        ElixirMake.Artefact.archive_filename(app, version, nif_version, target)

      metadata = %{
        app: app,
        cached_tar_gz: Path.join([cache_dir, archived_artefact_file]),
        base_url: base_url,
        target: target,
        targets: all_supported_targets(),
        version: version
      }

      ElixirMake.Artefact.write_metadata(app, metadata)
    end

    :ok
  end
end
