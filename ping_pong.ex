defmodule PingPong do

  def first do
    receive do
      {sender_pid, :ping} ->
        send sender_pid, "pong"
      _ ->
        IO.puts "Message not recognized by ping"
    end
  end

  def second do
    receive do
      {sender_pid, :pong} ->
        send sender_pid, "ping"
      _ ->
        IO.puts "Message not recognized by pong"
    end
  end

  def init do
    ping_pid = spawn(PingPong, :first, [])
    pong_pid = spawn(PingPong, :second, [])

    [ping_pid, pong_pid]
  end

end
