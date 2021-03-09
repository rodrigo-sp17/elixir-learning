defmodule Pooly.Server do
  use GenServer

  defmodule State do
    defstruct sup: nil, size: nil, mfa: nil, monitors: nil, worker_sup: nil, workers: nil
  end

  #### API

  def start_link(pools_config) do
    GenServer.start_link(__MODULE__, pools_config, name: __MODULE__)
  end

  def checkout(pool_name) do
    GenServer.call(:"#{pool_name}Server", :checkout)
  end

  def checkin(pool_name, worker_pid) do
    GenServer.cast(:"#{pool_name}Server", {:checkin, worker_pid})
  end

  def status(pool_name) do
    GenServer.call(:"#{pool_name}Server", :status)
  end

  #### Callback

  def init(pools_config) do
    pools_config |> Enum.each(fn pool_config ->
      send(self(), {:start_pool, pool_config})
    end)
    {:ok, pools_config}
  end

  def handle_info({:start_pool, pool_config}, state) do
    {:ok, _pool_sup} = DynamicSupervisor.start_child(
      Pooly.PoolsSupervisor,
      supervisor_spec(pool_config)
    )
    {:noreply, state}
  end

  #### Helpers

  defp supervisor_spec(pool_config) do
    Supervisor.child_spec(Pooly.PoolSupervisor.child_spec(pool_config),
    id: :"#{pool_config[:name]}Supervisor")
  end
end
