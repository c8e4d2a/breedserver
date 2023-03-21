defmodule Bobo.Nftbox do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:mint_id, :integer, []}
  schema "nftboxes" do
    field :box_id, :string

    timestamps()
  end

  @spec changeset(
          {map, map}
          | %{
              :__struct__ => atom | %{:__changeset__ => map, optional(any) => any},
              optional(atom) => any
            },
          :invalid | %{optional(:__struct__) => none, optional(atom | binary) => any}
        ) :: Ecto.Changeset.t()
  @doc false
  def changeset(nftbox, attrs) do
    nftbox
    |> cast(attrs, [:box_id, :mint_id])
    |> validate_required([:box_id, :mint_id])
    |> unique_constraint(:box_id)
  end
end
