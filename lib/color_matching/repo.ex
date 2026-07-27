defmodule ColorMatching.Repo do
  use Ecto.Repo,
    otp_app: :color_matching,
    adapter: Ecto.Adapters.SQLite3
end
