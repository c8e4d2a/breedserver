defmodule Bobo.Repo.Migrations.CreateCreatureFragments do
  use Ecto.Migration

  def change do
    create table(:creature_fragments) do
      add :creature_id, references(:mints, on_delete: :nothing)
      add :fragment_id, references(:fragments, [column: :fragment_id, type: :string, on_delete: :nothing])

      timestamps()
    end

    create index(:creature_fragments, [:creature_id])
    create index(:creature_fragments, [:fragment_id])
  end
end
