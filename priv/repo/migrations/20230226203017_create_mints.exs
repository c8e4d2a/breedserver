defmodule Bobo.Repo.Migrations.CreateMints do
  use Ecto.Migration

  def change do
    create table(:mints) do
      add :name, :string
      add :unlocks, :string
      add :ipfs, :string
      add :description, :string
      add :meta, :string
      add :mint_price_in_nano_erg, :decimal
      add :payment_tx, :string
      add :payment_box_id, :string
      add :token_id, :string
      add :confirmations, :integer
      add :mint_tx, :string
      add :receiver_address, :string
      add :is_creature, :boolean
      add :is_scroll, :boolean

      add :from_ritual_id, :bigint
      add :cd_minutes, :integer
      add :last_use, :utc_datetime
      add :gen, :integer
      add :parents, :string
      add :lease_price, :decimal
      add :lease_box_id, :string
      add :after_lease_return_to_owner, :boolean
      add :release_in_progress, :boolean
      add :breed_in_progress, :boolean
      add :release_tx, :string
      add :burn_tx, :string

      add :project, :string
      add :creature_name, :string

      timestamps()
    end
  end
end
