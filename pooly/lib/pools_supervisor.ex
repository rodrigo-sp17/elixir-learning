defmodule Pooly.PoolsSupervisor do
  use DynamicSupervisor

  #### API

  def start_link(_init_args) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start_child(child_specs) do
    DynamicSupervisor.start_child(__MODULE__, child_specs)
  end

  #### Callbacks

  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
