defmodule BoboWeb.Router do
  use BoboWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", BoboWeb do
    pipe_through :api
  end

  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      #forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
