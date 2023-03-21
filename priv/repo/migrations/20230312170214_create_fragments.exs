defmodule Bobo.Repo.Migrations.CreateFragments do
  use Ecto.Migration

  def change do
    create table(:fragments, primary_key: false) do
      add :fragment_id, :string, primary_key: true
      add :project, :string

      timestamps()
    end
  end
end
