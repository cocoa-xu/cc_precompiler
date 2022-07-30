defmodule CcPrecompilerTest do
  use ExUnit.Case
  doctest CcPrecompiler

  test "greets the world" do
    assert CcPrecompiler.hello() == :world
  end
end
