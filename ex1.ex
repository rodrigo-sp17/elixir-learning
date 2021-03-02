defmodule ListSum do
  def sum([]), do: 0

  def sum([head]) when is_number(head), do: head

  def sum([head | tail]) when is_number(head) do
    head + sum(tail)
  end
end

defmodule TransformList do
  # Transforms the list with piping
  def transform_pipe(list_num) do
    List.flatten(list_num) |> Enum.map(fn x -> x * x end) |> Enum.reverse()
  end

  # Transforms the list with pattern matching
  def transform(list_num) do
    case list_num do
      [] -> []
      [head] ->
        if is_list(head) do
          transform(List.flatten(head))
        else
          [head * head]
        end
      [head | tail] ->
        transform(tail) ++ [head * head]
    end
  end
end
