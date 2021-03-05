defmodule MSupervisorTest do
  use ExUnit.Case
  doctest MSupervisor

  test "greets the world" do
    assert MSupervisor.hello() == :world
  end
end
