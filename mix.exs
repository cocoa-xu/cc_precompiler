defmodule CCPrecompiler.MixProject do
  use Mix.Project

  @app :cc_precompiler
  @version "0.1.0"
  @github_url "https://github.com/cocoa-xu/cc_precompiler"
  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "NIF library Precompiler that Uses C/C++ (cross-)compiler.",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :eex]
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.7.0-dev", runtime: false, github: "elixir-lang/elixir_make"}
    ]
  end

  defp package do
    [
      name: Atom.to_string(@app),
      files: ~w(lib README* LICENSE* *.md),
      licenses: ["Apache-2.0"],
      links: links()
    ]
  end

  defp links do
    %{
      "GitHub" => @github_url,
      "Readme" => "#{@github_url}/blob/v#{@version}/README.md",
      "Precompilation Guide" => "#{@github_url}/blob/v#{@version}/PRECOMPILATION_GUIDE.md"
    }
  end
end
