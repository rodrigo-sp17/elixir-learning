defmodule Pooly.PoolServer do
  use GenServer

  defmodule State do
    defstruct sup: nil, size: nil, mfa: nil, monitors: nil,
    name: nil, worker_sup: nil, workers: nil
  end

  #### API

  def start_link([sup, pool_config]) do
    GenServer.start_link(__MODULE__, [sup, pool_config], name: name(pool_config[:name]))
  end

  def checkout(pool_name) do
    GenServer.call(name(pool_name), :checkout)
  end

  def checkin(pool_name, worker_pid) do
    GenServer.cast(name(pool_name), {:checkin, worker_pid})
  end

  def status(pool_name) do
    GenServer.call(name(pool_name), :status)
  end

  #### Callbacks

  def init([sup, pool_config]) do
    Process.flag(:trap_exit, true)
    monitors = :ets.new(:monitors, [:private])
    init(pool_config, %State{sup: sup, monitors: monitors})
  end

  def init([{:name, name} | rest], state) do
    init(rest, %{state | name: name})
  end

  def init([{:mfa, mfa} | rest], state) do
    init(rest, %{state | mfa: mfa})
  end

  def init([{:size, size} | rest], state) do
    init(rest, %{state | size: size})
  end

  def init([_ | rest], state) do
    init(rest, state)
  end

  def init([], state) do
    send(self(), :start_worker_supervisor)
    {:ok, state}
  end

  def handle_call(:checkout, {from_pid, _ref}, %{workers: workers,
   monitors: monitors} = state) do
    case workers do
      [worker | rest] ->
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | workers: rest}}
      [] ->
        {:reply, :noproc, state}
    end
  end

  def handle_call(:status, _from, %{workers: workers,
   monitors: monitors} = state) do
    {:reply, {length(workers), :ets.info(monitors, :size)}, state}
  end

  def handle_cast({:checkin, worker_pid}, %{workers: workers,
  monitors: monitors} = state) do
    case :ets.lookup(monitors, worker_pid) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        {:noreply, %{state | workers: [pid | workers]}}
      [] ->
        {:noreply, state}
    end
  end

  def handle_info(:start_worker_supervisor, state = %{sup: sup,
  mfa: mfa, name: name, size: size}) do
    {:ok, worker_sup} = Supervisor.start_child(
      sup,
      supervisor_spec(name, mfa)
    )

    workers = prepopulate(size, worker_sup, mfa)

    {:noreply, %{state | worker_sup: worker_sup, workers: workers}}
  end

  def handle_info({:DOWN, ref, _, _ ,_}, state = %{monitors: monitors,
  workers: workers}) do
    case :ets.match(monitors, {:"$1", ref}) do
      [[pid]] ->
        true = :ets.delete(monitors, pid)
        {:noreply, %{state | workers: [pid | workers]}}
        [[]] ->
          {:noreply, state}
        end
      end

  def handle_info({:EXIT, worker_sup, reason}, state = %{worker_sup: worker_sup}) do
    {:stop, reason, state}
  end

  def handle_info({:EXIT, pid, _reason}, state = %{monitors: monitors,
  workers: workers, worker_sup: worker_sup}) do
    IO.puts "Received message from presumed worker #{inspect pid}"
    case :ets.lookup(monitors, pid) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(pid)
        {:noreply, %{state | workers: [new_worker(worker_sup, {SampleWorker, :start_link, []}) | workers]}}
    [] ->
      {:noreply, state}
    end
  end

  def terminate(_reason, _state) do
    :ok
  end

  #### Helper methods

  defp name(pool_name) do
    :"#{pool_name}Server"
  end

  defp supervisor_spec(name, mfa) do
    Supervisor.child_spec(
      Pooly.WorkerSupervisor.child_spec([self(), mfa]),
      id: name <> "WorkerSupervisor",
      restart: :temporary
    )
  end

  defp prepopulate(size, sup, mfa) do
    prepopulate(size, sup, [], mfa)
  end

  defp prepopulate(size, _sup, workers, _mfa) when size < 1 do
    workers
  end

  defp prepopulate(size, sup, workers, mfa) do
    prepopulate(size - 1, sup, [new_worker(sup, mfa) | workers], mfa)
  end

  defp new_worker(sup, {mod, _func, _arg}) do
    {:ok, worker} = DynamicSupervisor.start_child(sup, mod)
    worker
  end
end
