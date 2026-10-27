defmodule Gamend.Repo.Migrations.CreateGithubInstallations do
  @moduledoc """
  `github_installations` (`Gamend.GitHub`): which installations of the
  server's GitHub App a user may use.

  One row per user × installation rather than one per installation: several
  members of an organisation may each connect it, and each of them should see
  it on their own picker without any of them being told about the others.
  """

  use Ecto.Migration

  def change do
    create table(:github_installations) do
      add :installation_id, :bigint, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :account_login, :string
      add :account_id, :bigint
      add :account_type, :string
      add :repository_selection, :string
      add :suspended_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_installations, [:user_id, :installation_id],
             name: :github_installations_user_id_installation_id_index
           )

    # The webhook's lifecycle events find every user's row by GitHub's id.
    create index(:github_installations, [:installation_id])
  end
end
