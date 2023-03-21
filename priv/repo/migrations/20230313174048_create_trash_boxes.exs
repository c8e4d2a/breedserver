defmodule Bobo.Repo.Migrations.CreateTrashBoxes do
  use Ecto.Migration

  def change do
    create table(:trash_boxes, primary_key: false) do
      add :box_id, :string, primary_key: true

      timestamps()
    end
  end
end
