defmodule Bobo.Repo do
  use Ecto.Repo,
    otp_app: :bobo,
    adapter: Ecto.Adapters.Postgres
end
