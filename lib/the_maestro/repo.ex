defmodule TheMaestro.Repo do
  use Ecto.Repo,
    otp_app: :the_maestro,
    adapter: Ecto.Adapters.Postgres
end
