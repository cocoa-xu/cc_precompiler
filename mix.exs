defmodule CCPrecompiler.MixProject do
  use Mix.Project

  def project do
    [
      app: :cc_precompiler,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :eex, :elixir_make]
    ]
  end

  defp deps do
    [
      # todo: change this to hex.pm once elixir-lang/elixir_make#56 is merged
      {:elixir_make, "~> 0.6", runtime: false, github: "cocoa-xu/elixir_make", branch: "cx-improve-precompiler"}
    ]
  end
end
