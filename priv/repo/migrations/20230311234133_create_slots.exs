defmodule Bobo.Repo.Migrations.CreateSlots do
  use Ecto.Migration

  def change do
    create table(:slots) do
      add :own_creature_token_id, :string
      add :request_creature_token_id, :string
      add :return_creature_on_token_release, :boolean
      add :bid_erg, :decimal
      add :done, :boolean
      add :assigned_creature_token_id, :string
      add :scroll_id, references(:mints, on_delete: :nothing)

      timestamps()
    end

    create index(:slots, [:scroll_id])
  end
end
