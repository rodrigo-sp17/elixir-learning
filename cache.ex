defmodule Cache do
  use GenServer

  @name C

  ## Client API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: C])
  end

  def write(key, value) do
    GenServer.cast(@name, {:pair, [key, value]})
  end

  def read(key) do
    GenServer.call(@name, {:key, key})
  end

  def delete(key) do
    GenServer.cast(@name, {:delete, key})
  end

  def clear do
    GenServer.cast(@name, :clear)
  end

  def exist?(key) do
    GenServer.call(@name, {:exist, key})
  end

  def stop do
    GenServer.cast(@name, :stop)
  end

  ## Server callbacks
  def init(:ok) do
    {:ok, %{}}
  end

  def handle_cast({:pair, [key, value]}, stats) do
    new_stats = update_stats(stats, [key, value])
    {:noreply, new_stats}
  end

  def handle_cast({:delete, key}, stats) do
    new_stats = delete_from_stats(stats, key)
    {:noreply, new_stats}
  end

  def handle_cast(:clear, _stats) do
    {:noreply, %{}}
  end

  def handle_cast(:stop, stats) do
    IO.puts "Stopping server"
    {:stop, :normal, stats}
  end

  def handle_call({:key, key}, _from, stats) do
    result = Map.get(stats, key, 'Map is empty')
    {:reply, result, stats}
  end

  def handle_call({:exist, key}, _from, stats) do
    result = Map.has_key?(stats, key)
    {:reply, result, stats}
  end

  def terminate(reason, stats) do
    IO.puts "Server terminated because of #{inspect reason}"
      inspect stats
    :ok
  end

  ## Helper functions
  defp update_stats(old_stats, [key, value]) do
    case Map.has_key?(old_stats, key) do
      true ->
        Map.update!(old_stats, key, fn old -> value end)
      false ->
        Map.put_new(old_stats, key, value)
    end
  end

  defp delete_from_stats(old_stats, key) do
    case Map.has_key?(old_stats, key) do
      true ->
        Map.delete(old_stats, key)
      false ->
        old_stats
    end
  end

end
