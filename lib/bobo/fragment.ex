defmodule Bobo.Fragment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:fragment_id, :string, []}
  schema "fragments" do
    field :project, :string

    timestamps()
  end

  @doc false
  def changeset(fragment, attrs) do
    fragment
    |> cast(attrs, [:fragment_id, :project])
    |> validate_required([:fragment_id])
  end
end
