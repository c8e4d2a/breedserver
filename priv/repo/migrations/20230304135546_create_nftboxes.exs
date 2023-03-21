defmodule Bobo.Repo.Migrations.CreateNftboxes do
  use Ecto.Migration

  def change do
    create table(:nftboxes, primary_key: false) do
      add :mint_id, references(:mints, on_delete: :nothing), primary_key: true
      add :box_id, :string

      timestamps()
    end

    create index(:nftboxes, [:mint_id])
  end
end
