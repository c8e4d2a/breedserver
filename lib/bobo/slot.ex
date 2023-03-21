defmodule Bobo.Slot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "slots" do
    field :assigned_creature_token_id, :string
    field :bid_erg, :decimal
    field :own_creature_token_id, :string
    field :request_creature_token_id, :string
    field :return_creature_on_token_release, :boolean
    field :scroll_id, :id
    field :done, :boolean

    timestamps()
  end

  @doc false
  def changeset(slot, attrs) do
    slot
    |> cast(attrs, [:own_creature_token_id, :request_creature_token_id, :return_creature_on_token_release, :bid_erg, :assigned_creature_token_id, :scroll_id, :done])
    |> validate_required([:scroll_id])
  end
end
