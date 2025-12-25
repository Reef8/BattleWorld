defmodule BracketBattle.Chat do
  @moduledoc """
  Context for tournament chat functionality.
  """

  import Ecto.Query
  alias BracketBattle.Repo
  alias BracketBattle.Chat.Message

  @doc "Send a chat message"
  def send_message(tournament_id, user_id, content) do
    %Message{}
    |> Message.changeset(%{
      tournament_id: tournament_id,
      user_id: user_id,
      content: content
    })
    |> Repo.insert()
    |> broadcast_message()
  end

  @doc "Get recent messages"
  def get_messages(tournament_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    before_id = Keyword.get(opts, :before)

    query = from(m in Message,
      where: m.tournament_id == ^tournament_id and is_nil(m.deleted_at),
      order_by: [desc: m.inserted_at],
      limit: ^limit,
      preload: [:user]
    )

    query = if before_id do
      from m in query, where: m.id < ^before_id
    else
      query
    end

    Repo.all(query)
    |> Enum.reverse()
  end

  @doc "Delete message (soft delete, admin only)"
  def delete_message(message_id, _admin_user_id) do
    from(m in Message, where: m.id == ^message_id)
    |> Repo.update_all(set: [deleted_at: DateTime.utc_now()])

    Phoenix.PubSub.broadcast(
      BracketBattle.PubSub,
      "chat:#{message_id}",
      {:message_deleted, message_id}
    )

    :ok
  end

  @doc "Get message by ID"
  def get_message!(id), do: Repo.get!(Message, id)

  defp broadcast_message({:ok, message} = result) do
    message = Repo.preload(message, :user)

    Phoenix.PubSub.broadcast(
      BracketBattle.PubSub,
      "tournament:#{message.tournament_id}:chat",
      {:new_message, message}
    )

    result
  end
  defp broadcast_message(error), do: error
end
