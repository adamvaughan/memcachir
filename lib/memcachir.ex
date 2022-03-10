defmodule Memcachir do
  @moduledoc """
  Module with a friendly API for memcached servers.

  It provides connection pooling, and cluster support.

  ## Examples

      {:ok} = Memcachir.set("hello", "world")
      {:ok, "world"} = Memcachir.get("hello")

  """
  use Application

  alias Memcachir.{
    Cluster,
    Pool,
    Supervisor
  }

  def start(_type, _args) do
    opts = Application.get_all_env(:memcachir)
    Supervisor.start_link(opts)
  end

  @doc """
  Gets the value associated with the key. Returns `{:error, "Key not found"}`
  if the given key doesn't exist.
  """
  def get(key, opts \\ []) do
    case Cluster.get_node(key) do
      {:ok, node} -> execute(&Memcache.get/3, node, [key, opts])
      {:error, reason} -> {:error, "unable to get: #{reason}"}
    end
  end

  @doc """
  Accepts a list of mcached keys, and returns either `{:ok, %{key => val}}` for each
  found key or `{:error, any}`.
  """
  def mget(keys, opts \\ []) do
    case group_by_node(keys) do
      {:ok, grouped_keys} -> exec_parallel(&Memcache.multi_get/3, grouped_keys, [opts])
      {:error, reason} -> {:error, "unable to get: #{reason}"}
    end
  end

  @doc """
  Accepts a list of `{key, val}` pairs and returns the store results for each
  node touched.
  """
  def mset(commands, opts \\ []) do
    case group_by_node(commands, &elem(&1, 0)) do
      {:ok, grouped_keys} -> exec_parallel(&Memcache.multi_set/3, grouped_keys, [opts], &Enum.concat/2)
      {:error, reason} -> {:error, "unable to set: #{reason}"}
    end
  end

  @doc """
  Multi-set with cas option.
  """
  def mset_cas(commands, opts \\ []) do
    case group_by_node(commands, &elem(&1, 0)) do
      {:ok, grouped_keys} -> exec_parallel(&Memcache.multi_set_cas/3, grouped_keys, [opts], &Enum.concat/2)
      {:error, reason} -> {:error, "unable to set: #{reason}"}
    end
  end

  @doc """
  increments the key by value.
  """
  def incr(key, value \\ 1, opts \\ []) do
    case Cluster.get_node(key) do
      {:ok, node} -> execute(&Memcache.incr/3, node, [key, [{:by, value} | opts]])
      {:error, reason} -> {:error, "unable to inc: #{reason}"}
    end
  end

  @doc """
  Sets the key to value.

  Valid option are:
    * `:ttl` - The time in seconds that the value will be stored.

  """
  def set(key, value, opts \\ []) do
    {retry, opts} = Keyword.pop(opts, :retry, false)

    case Cluster.get_node(key) do
      {:ok, node} -> execute(&Memcache.set/4, node, [key, value, opts], retry)
      {:error, reason} -> {:error, "unable to set: #{reason}"}
    end
  end

  @doc """
  Removes the item with the specified key.

  Returns `{:ok, :deleted}`.
  """
  def delete(key) do
    case Cluster.get_node(key) do
      {:ok, node} -> execute(&Memcache.delete/2, node, [key])
      {:error, reason} -> {:error, "unable to delete: #{reason}"}
    end
  end

  @doc """
  Removes all the items from the server.

  Returns `{:ok}`.
  """
  def flush(opts \\ []) do
    execute(&Memcache.flush/2, Cluster.servers(), [opts])
  end

  defp execute(fun, node, args, retry \\ false)
  defp execute(_fun, [], _args, _retry) do
    {:error, "unable to flush: no_nodes"}
  end
  defp execute(fun, [node | nodes], args, retry) do
    if length(nodes) > 0 do
      execute(fun, nodes, args, retry)
    end

    execute(fun, node, args, retry)
  end
  defp execute(fun, node, args, retry) do
    try do
      node
      |> Pool.poolname()
      |> :poolboy.transaction(&apply(fun, [&1 | args]))
      |> case do
        {:error, :closed} = error ->
          if retry do
            IO.puts("Retrying")
            execute(fun, node, args, false)
          else
            Memcachir.Cluster.mark_node(node)
            error
          end
        other -> other
      end
    catch
      :exit, _ ->
        if retry do
          IO.puts("Retrying")
          execute(fun, node, args, false)
        else
          Memcachir.Cluster.mark_node(node)
          {:error, "Node not available"}
        end
    end
  end

  @doc """
  Accepts a memcache operation closure, a grouped map of `%{node => args}` and
  executes the operations in parallel for all given nodes.

  The result is of form `{:ok, enumerable}` where enumerable is the merged
  result of all operations.

  Additionally, you can pass `args` to supply memcache ops to each of the
  executions and `merge_fun` (a 2-arity func) which configures how the result
  is merged into the final result set.

  For instance, `mget/2` returns a map of key, val pairs in its result, and
  utilizes `Map.merge/2`.
  """
  def exec_parallel(fun, grouped, args \\ [], merge_fun \\ &Map.merge/2) do
    grouped
    |> Enum.map(fn {node, val} -> Task.async(fn -> execute(fun, node, [val | args]) end) end)
    |> Enum.map(&Task.await/1)
    |> Enum.reduce({%{}, []}, fn
      {:ok, result}, {acc, errors} -> {merge_fun.(acc, result), errors}
      error, {acc, errors} -> {acc, [error | errors]}
    end)
    |> case do
      {map, [error | _]} when map_size(map) == 0 -> error
      {result, _} -> {:ok, result}
    end
  end

  defp group_by_node(commands, get_key \\ fn k -> k end) do
    key_to_command = Enum.into(commands, %{}, fn c -> {get_key.(c), c} end)

    commands
    |> Enum.map(get_key)
    |> Cluster.get_nodes()
    |> case do
      {:ok, keys_to_nodes} ->
        key_fn   = fn {_, n} -> n end
        value_fn = fn {k, _} -> key_to_command[k] end
        nodes_to_keys = Enum.group_by(keys_to_nodes, key_fn, value_fn)

        {:ok, nodes_to_keys}
      {:error, error} -> {:error, error}
    end
  end
end
