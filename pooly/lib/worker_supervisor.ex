defmodule Pooly.WorkerSupervisor do
  use DynamicSupervisor

  #######
  # API #
  #######

  def start_link(pool_server) do
    DynamicSupervisor.start_link(__MODULE__, pool_server)
  end

  def start_child(m) do
    DynamicSupervisor.start_child(__MODULE__,
     Supervisor.child_spec(m, shutdown: 5000))
  end

  #############
  # Callbacks #
  #############

  def init([sup, _mfa]) when is_pid(sup) do
    Process.link(sup)
    opts = [
          strategy: :one_for_one,
          max_restarts: 5,
          max_seconds: 5
    ]

    DynamicSupervisor.init(opts)
  end
end
