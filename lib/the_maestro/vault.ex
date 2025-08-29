defmodule TheMaestro.Vault do
  @moduledoc """
  Vault configuration for encrypting sensitive data at rest.
  
  Uses Cloak to provide AES-256-GCM encryption for sensitive fields like
  OAuth tokens and API keys stored in the database. Encryption keys are
  derived from the SECRET_KEY_BASE environment variable.
  
  ## Security Features
  
  - AES-256-GCM authenticated encryption
  - Key derivation from SECRET_KEY_BASE
  - Automatic encryption/decryption via Ecto types
  - JSON support for complex data structures
  
  ## Configuration
  
  The encryption key is automatically derived from the SECRET_KEY_BASE
  environment variable configured in runtime.exs. No additional setup required.
  
  ## Usage
  
  This vault is used automatically by the EncryptedCredentials Ecto type.
  No direct interaction with this module is needed.
  """
  
  use Cloak.Vault, otp_app: :the_maestro

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(
        config, 
        :ciphers, 
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: decode_env()}
      )

    {:ok, config}
  end

  defp decode_env do
    # Derive encryption key from SECRET_KEY_BASE (same as Phoenix sessions)
    secret_key_base = 
      System.get_env("SECRET_KEY_BASE") || 
      Application.get_env(:the_maestro, TheMaestroWeb.Endpoint)[:secret_key_base] ||
      raise "SECRET_KEY_BASE environment variable not set"

    # Use the first 32 bytes (256 bits) of SECRET_KEY_BASE for encryption key
    secret_key_base
    |> String.slice(0, 32)
    |> :binary.bin_to_list()
  end
end