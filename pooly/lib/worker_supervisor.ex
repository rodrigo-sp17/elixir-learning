defmodule Pooly.WorkerSupervisor do
  use DynamicSupervisor

  #######
  # API #
  #######

  def start_link(_init_args) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start_child(m) do
    DynamicSupervisor.start_child(__MODULE__, m)
  end

  #############
  # Callbacks #
  #############

  def init(_arg) do
    opts = [
          strategy: :one_for_one,
          max_restarts: 5,
          max_seconds: 5
        ]

    DynamicSupervisor.init(opts)
  end
end
