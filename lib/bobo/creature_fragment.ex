defmodule Bobo.CreatureFragment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "creature_fragments" do

    field :creature_id, :id
    field :fragment_id, :string

    timestamps()
  end

  @doc false
  def changeset(creature_fragment, attrs) do
    creature_fragment
    |> cast(attrs, [:creature_id, :fragment_id, :inserted_at, :updated_at])
    |> validate_required([:creature_id, :fragment_id])
  end
end
