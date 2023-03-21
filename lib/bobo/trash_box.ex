defmodule Bobo.TrashBox do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:box_id, :string, []}
  schema "trash_boxes" do

    timestamps()
  end

  @doc false
  def changeset(trash_box, attrs) do
    trash_box
    |> cast(attrs, [:box_id])
    |> validate_required([:box_id])
  end
end
