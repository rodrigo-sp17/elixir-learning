defmodule Pooly.PoolServer do
  use GenServer

  defmodule State do
    defstruct sup: nil, size: nil, mfa: nil, monitors: nil,
    name: nil, worker_sup: nil, workers: nil, overflow: nil, max_overflow: nil,
    waiting: nil
  end

  #### API

  def start_link([sup, pool_config]) do
    GenServer.start_link(__MODULE__, [sup, pool_config], name: name(pool_config[:name]))
  end

  def checkout(pool_name, block, timeout) do
    GenServer.call(name(pool_name), {:checkout, block}, timeout)
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
    waiting = :queue.new()
    init(pool_config, %State{sup: sup, monitors: monitors, waiting: waiting,
     overflow: 0})
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

  def init([{:max_overflow, max_overflow} | rest], state) do
    init(rest, %{state | max_overflow: max_overflow})
  end

  def init([_ | rest], state) do
    init(rest, state)
  end

  def init([], state) do
    send(self(), :start_worker_supervisor)
    {:ok, state}
  end

  def handle_call({:checkout, block}, {from_pid, _ref} = from, state) do
    %{worker_sup: worker_sup,
      workers: workers,
      monitors: monitors,
      waiting: waiting,
      overflow: overflow,
      max_overflow: max_overflow} = state

    case workers do
      [worker | rest] ->
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | workers: rest}}
      [] when max_overflow > 0 and overflow < max_overflow ->
        worker = new_worker(worker_sup, {SampleWorker, :start_link, []})
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | overflow: overflow + 1}}
      [] when block == true ->
        ref = Process.monitor(from_pid)
        waiting = :queue.in({from, ref}, waiting)
        {:noreply, %{state | waiting: waiting}, :infinity}
      [] ->
        {:reply, :full, state}
    end
  end

  def handle_call(:status, _from, %{workers: workers,
   monitors: monitors} = state) do
    {:reply, {state_name(state), length(workers), :ets.info(monitors, :size)}, state}
  end

  def handle_cast({:checkin, worker_pid}, %{monitors: monitors} = state) do
    case :ets.lookup(monitors, worker_pid) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        new_state = handle_checkin(pid, state)
        {:noreply, new_state}
      [] ->
        IO.puts "Already checked-in"
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
    IO.puts "Client is down. Handling..."
    case :ets.match(monitors, {:"$1", ref}) do
      [[pid]] ->
        true = :ets.delete(monitors, pid)
        {:noreply, %{state | workers: [pid | workers]}}
        [[]] ->
          {:noreply, state}
        end
      end

  def handle_info({:EXIT, worker_sup, reason}, state = %{worker_sup: worker_sup}) do
    IO.puts "Handling worker sup gone"
    {:stop, reason, state}
  end

  def handle_info({:EXIT, pid, _reason}, state = %{monitors: monitors}) do
    IO.puts "Handling worker gone"
    case :ets.lookup(monitors, pid) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        new_state = handle_worker_exit(pid, state)
        {:noreply, new_state}
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

  defp state_name(%{overflow: overflow, max_overflow: max_overflow,
   workers: workers}) when overflow < 1 do
    case length(workers) == 0 do
      true ->
        if max_overflow < 1 do
          :full
        else
          :overflow
        end
      false ->
        :ready
    end
  end

  defp state_name(%{overflow: max_overflow, max_overflow: max_overflow}) do
    :full
  end

  defp state_name(_state) do
    :overflow
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
    IO.puts "Spawning worker"
    {:ok, worker} = DynamicSupervisor.start_child(sup, mod)
    Process.link(worker)
    worker
  end

  defp handle_checkin(pid, state) do
    %{
      worker_sup: worker_sup,
      workers: workers,
      monitors: monitors,
      waiting: waiting,
      overflow: overflow
    } = state

    case :queue.out(waiting) do
      {{:value, {from, ref}}, left} ->
        true = :ets.insert(monitors, {pid, ref})
        GenServer.reply(from, pid)
        %{state | waiting: left}

      {:empty, empty} when overflow > 0 ->
        :ok = dismiss_worker(worker_sup, pid)
        %{state | waiting: empty, overflow: overflow - 1}

      {:empty, empty} ->
        %{state | waiting: empty, workers: [pid | workers], overflow: 0}
    end

  end

  defp handle_worker_exit(_pid, state) do
    %{
      worker_sup: worker_sup,
      workers: workers,
      monitors: monitors,
      waiting: waiting,
      overflow: overflow
    } = state

    case :queue.out(waiting) do
      {{:value, {from, ref}}, left} ->
        worker = new_worker(worker_sup, {SampleWorker, :start_link, []})
        :true = :ets.insert(monitors, {worker, ref})
        GenServer.reply(from, worker)
        %{state | waiting: left}

      {:empty, empty} when overflow > 0 ->
        %{state | overflow: overflow - 1, waiting: empty}

      {:empty, empty} ->
        workers = [new_worker(worker_sup, {SampleWorker, :start_link, []}) | workers]
        %{state | workers: workers, waiting: empty}
    end
  end

  defp dismiss_worker(sup, pid) do
    true = Process.unlink(pid)
    Supervisor.terminate_child(sup, pid)
  end
end
