defmodule SampleWorker do
  use GenServer, restart: :temporary

  #### API
  def start_link(_args) do
    GenServer.start_link(__MODULE__, :ok, [])
  end

  def work_for(pid, duration) do
    GenServer.cast(pid, {:work_for, duration})
  end

  def work(duration) do
    GenServer.call(__MODULE__, {:work, duration})
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  #### Callbacks
  def init(:ok) do
    {:ok, []}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call({:work, duration}, _from, state) do
    :timer.sleep(duration)
    {:reply, :finished_work, state}
  end

  def handle_cast({:work_for, duration}, state) do
    IO.puts "Sleeping for #{inspect duration}ms"
    :timer.sleep(duration)
    IO.puts "Times has ended"
    {:stop, :normal, state}
  end
end
