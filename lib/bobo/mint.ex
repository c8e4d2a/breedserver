defmodule Bobo.Mint do
  use Ecto.Schema
  import Ecto.Changeset

  schema "mints" do
    field :confirmations, :integer
    field :description, :string
    field :ipfs, :string
    field :meta, :string
    field :mint_price_in_nano_erg, :decimal
    field :mint_tx, :string
    field :receiver_address, :string
    field :name, :string
    field :unlocks, :string
    field :payment_box_id, :string
    field :token_id, :string
    field :payment_tx, :string
    field :is_creature, :boolean
    field :is_scroll, :boolean

    field :from_ritual_id, :integer
    field :cd_minutes, :integer
    field :last_use, :naive_datetime
    field :gen, :integer
    field :parents, :string
    field :lease_price, :decimal
    field :lease_box_id, :string
    field :after_lease_return_to_owner, :boolean
    field :release_in_progress, :boolean
    field :breed_in_progress, :boolean
    field :release_tx, :string
    field :burn_tx, :string

    field :creature_name, :string
    field :project, :string

    timestamps()
  end

  @doc false
  def changeset(mint, attrs) do
    mint
    |> cast(attrs, [:id, :name, :ipfs, :description, :meta, :mint_price_in_nano_erg, :payment_tx, :payment_box_id, :confirmations, :mint_tx, :receiver_address, :unlocks, :is_creature, :is_scroll, :token_id,
    :from_ritual_id,
    :cd_minutes,
    :last_use,
    :gen,
    :parents,
    :lease_price,
    :lease_box_id,
    :after_lease_return_to_owner,
    :release_in_progress,
    :breed_in_progress,
    :release_tx,
    :burn_tx,
    :project, :creature_name])
    |> validate_required([:name])
  end
end
