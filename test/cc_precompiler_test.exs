defmodule Mix.Tasks.ElixirMake.CCPrecompiler.Test do
  use ExUnit.Case
  doctest CCPrecompiler

  describe "all_supported_targets when fetching" do
    test "without include_default_ones" do
      assert [
        "aarch64-apple-darwin",
        "x86_64-apple-darwin",
        "aarch64-linux-gnu",
        "armv7l-linux-gnueabihf",
        "i686-linux-gnu",
        "powerpc64le-linux-gnu",
        "riscv64-linux-gnu",
        "s390x-linux-gnu",
        "x86_64-linux-gnu",
        "x86_64-windows-msvc"
      ] == CCPrecompiler.all_supported_targets(:fetch)
    end
  end
end
