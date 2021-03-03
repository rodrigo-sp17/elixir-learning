defmodule Metlogic do
  @moduledoc """
  Documentation for `Metlogic`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Metlogic.hello()
      :world

  """
  def hello do
    :world
  end

  def temperatures_of(cities) do
    coordinator_pid =
      spawn(Metlogic.Coordinator, :loop, [[], Enum.count(cities)])

    cities |> Enum.each(fn city ->
      worker_pid = spawn(Metlogic.Worker, :loop, [])
      send worker_pid, {coordinator_pid, city}
    end)
  end

end
