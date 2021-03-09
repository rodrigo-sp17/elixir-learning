defmodule Pooly.Supervisor do
  use Supervisor

  def start_link(pools_config) do
    Supervisor.start_link(__MODULE__, pools_config, name: __MODULE__)
  end


  def init(pools_config) do
    children = [
      Pooly.PoolsSupervisor.child_spec([]),
      Pooly.Server.child_spec(pools_config)
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
