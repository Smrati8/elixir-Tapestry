defmodule Proj3 do
  use GenServer

  def main do
    # Input of the nodes, Topology and Algorithm
    input = System.argv()
    [numNodes, numRequests] = input
    numNodes = String.to_integer(numNodes)
    numRequests = String.to_integer(numRequests)

    # Associating all nodes with their PID's
    allNodes =
      Enum.map(1..numNodes, fn x ->
        pid = start_node()
        updatePIDState(pid, x)
        pid
      end)

    indexed_actors =
      Stream.with_index(allNodes, 1)
      |> Enum.reduce(%{}, fn {pids, nodeID}, acc ->
        Map.put(acc, String.to_charlist(:crypto.hash(:sha, "#{nodeID}") |> Base.encode16()), pids)
      end)

    list_of_hexValues =
      for {hash_key, _pid} <- indexed_actors do
        hash_key
      end

    Enum.map(indexed_actors, fn {hash_key, _pid} ->
      fill_routing_table(
        hash_key,
        list_of_hexValues -- [hash_key]
      )
    end)

    hopping_list =
      Enum.reduce(indexed_actors, [], fn {source_ID, pid}, final_hop_list ->
        destinationList = Enum.take_random(list_of_hexValues -- [source_ID], numRequests)

        final_hop_list ++
          implementing_tapestry(
            source_ID,
            pid,
            destinationList,
            indexed_actors
          )
      end)

    max_hops = Enum.max(hopping_list)
    IO.puts("Maximum Hops = #{max_hops}")
  end

  def implementing_tapestry(
        node_ID,
        pid,
        destinationList,
        indexed_actors
      ) do
    Enum.reduce(destinationList, [], fn dest_ID, hop_list ->
      hop_list ++
        [
          GenServer.call(
            pid,
            {:UpdateNextHop, node_ID, dest_ID, 1, indexed_actors}
          )
        ]
    end)
  end

  def nextHop(new_node_ID, dest_ID, total_hops, indexed_actors) do
    GenServer.call(
      Map.fetch!(indexed_actors, new_node_ID),
      {:UpdateNextHop, new_node_ID, dest_ID, total_hops, indexed_actors}
    )
  end

  def fill_routing_table(hash_key, list_of_neighbors) do
    Enum.reduce(
      list_of_neighbors,
      :ets.new(String.to_atom("Table_#{hash_key}"), [:named_table, :public]),
      fn neighbor_key, _acc ->
        key = commonPrefix(hash_key, neighbor_key)

        if :ets.lookup(String.to_atom("Table_#{hash_key}"), key) != [] do
          [{_, already_in_map_hexVal}] = :ets.lookup(String.to_atom("Table_#{hash_key}"), key)
          {hash_key_integer, _} = Integer.parse(List.to_string(hash_key), 16)
          {already_in_map_integer, _} = Integer.parse(List.to_string(already_in_map_hexVal), 16)
          {neighbor_key_integer, _} = Integer.parse(List.to_string(neighbor_key), 16)

          dist1 = abs(hash_key_integer - already_in_map_integer)
          dist2 = abs(hash_key_integer - neighbor_key_integer)

          if dist1 < dist2 do
            :ets.insert(String.to_atom("Table_#{hash_key}"), {key, already_in_map_hexVal})
          else
            :ets.insert(String.to_atom("Table_#{hash_key}"), {key, neighbor_key})
          end
        else
          :ets.insert(String.to_atom("Table_#{hash_key}"), {key, neighbor_key})
        end
      end
    )
  end

  def commonPrefix(hash_key, neighbor_key) do
    Enum.reduce_while(neighbor_key, 0, fn char2, level ->
      if Enum.at(hash_key, level) == char2,
        do: {:cont, level + 1},
        else: {:halt, {level, List.to_string([char2])}}
    end)
  end

  def init(:ok) do
    {:ok, {0, 1}}
  end

  def start_node() do
    {:ok, pid} = GenServer.start_link(__MODULE__, :ok, [])
    pid
  end

  def updatePIDState(pid, nodeID) do
    GenServer.call(pid, {:UpdatePIDState, nodeID})
  end

  def handle_call(
        {:UpdateNextHop, node_ID, dest_ID, total_hops, indexed_actors},
        _from,
        state
      ) do
    key = commonPrefix(node_ID, dest_ID)
    [{_, new_node_ID}] = :ets.lookup(String.to_atom("Table_#{node_ID}"), key)

    if(new_node_ID == dest_ID) do
      {:reply, total_hops, state}
    else
      final_hop_count =
        nextHop(
          new_node_ID,
          dest_ID,
          total_hops + 1,
          indexed_actors
        )

      {:reply, final_hop_count, state}
    end
  end

  # Handle call for associating specific Node with PID
  def handle_call({:UpdatePIDState, nodeID}, _from, state) do
    {a, b} = state
    state = {nodeID, b}
    {:reply, a, state}
  end
end

Proj3.main()
